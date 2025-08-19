// TODO: Make everything work in fifo order. I think this should immediately work as long as I emit the token earlier. 
    // I already have the logic necessary to make sure i don't read data that hasn't been stored (untested)

// TODO: Replace loop with find
// TODO: Remove memory size dependency on tile size, should just have banks be as large as possible
// TODO: Swap registers for SRAM
// TODO: rank shouldnt be a parameter, should be stored in a reg and parsed from a config input

package PMU;

import FIFO::*;
import Types::*;
import Vector::*;
import RegFile::*;
import ConfigReg::*;
import BankedMemory::*;
import Parameters::*;
import SetFreeList::*;
import SetUsageTracker::*;
import Unwrap::*;
import Operation::*;
import HelperFunctions::*;

// Interface that just exposes the modules existence
interface PMU_IFC;
    interface Operation_IFC operation;
    method Action put_data(ChannelMessage msg);
    method ActionValue#(ChannelMessage) get_token();
    method Action put_token(ChannelMessage msg);
    method ActionValue#(ChannelMessage) get_data();
    method Int#(32) get_cycle_count();
endinterface

// PMU module that processes between the FIFOs
module mkPMU#(
    Int#(32) rank                    // Rank of the current tile
)(PMU_IFC);

    // ============================================================================
    // Internal state
    // ============================================================================

    FIFO#(ChannelMessage) data_in <- mkFIFO;      // Values come in here
    FIFO#(ChannelMessage) token_out <- mkFIFO;    // Generated tokens go out here
    FIFO#(ChannelMessage) token_in <- mkFIFO;     // Tokens come back in here
    FIFO#(ChannelMessage) data_out <- mkFIFO;     // Retrieved values go out here

    // initialization and cycle count
    Reg#(Bit#(32)) cycle_count <- mkReg(0);
    Reg#(Bool) initialized <- mkReg(False);
    Reg#(Bit#(TLog#(MAX_ENTRIES))) first_entry_initialized_index <- mkReg(0);

    ConfigReg#(Bit#(TLog#(MAX_ENTRIES))) token_counter <- mkConfigReg(0);

    // storage usage tracking
    BankedMemory_IFC mem <- mkBankedMemory;
    SetFreeList_IFC free_list <- mkSetFreeList;
    SetUsageTracker_IFC usage_tracker <- mkSetUsageTracker;
    Reg#(StorageLocation) curr_loc <- mkReg(StorageLocation { set: 0, frame: 0, valid: False });
    ConfigReg#(Maybe#(SET_INDEX)) next_free_set <- mkConfigReg(tagged Invalid);

    // storage chain logic
    RegFile#(Bit#(TLog#(MAX_ENTRIES)), Maybe#(StorageAddr)) first_entry <- mkRegFileWCF(0, fromInteger(valueOf(MAX_ENTRIES) - 1));    
    RegFile#(Bit#(TLog#(MAX_ENTRIES)), Bool) token_complete <- mkRegFileWCF(0, fromInteger(valueOf(MAX_ENTRIES) - 1));
    Vector#(MAX_ENTRIES, ConfigReg#(Maybe#(StorageAddr))) next_table <- replicateM(mkConfigReg(tagged Invalid));
    // Vector#(MAX_ENTRIES, ConfigReg#(Bit#(TLog#(MAX_ENTRIES)))) pmu_id_table <- replicateM(mkConfigReg(0)); // TODO: Unused for static
    Reg#(StorageAddr) prev_stored <- mkReg(0);

    // load and deallocate registers
    Reg#(Maybe#(LoadState)) load_token <- mkReg(tagged Invalid);
    ConfigReg#(Maybe#(Bit#(TLog#(MAX_ENTRIES)))) deallocate_reg <- mkConfigReg(tagged Invalid);

    Reg#(Bool) read_inflight <- mkReg(False);
    FIFO#(LoadMeta) load_meta_q <- mkFIFO;

    // ============================================================================
    // Rule Orderings
    // ============================================================================

    (* execution_order = "cycle_counter, store_tile, next_free, continue_load_tile" *)
    (* execution_order = "cycle_counter, start_load_tile" *)
    (* execution_order = "next_free, retire_read" *)
    (* descending_urgency = "deallocate_token, store_tile" *)

    // ============================================================================
    // Main Logic Rules
    // ============================================================================

    rule deallocate_token (initialized &&& deallocate_reg matches tagged Valid .token_id);
        first_entry.upd(token_id, tagged Invalid);
        token_complete.upd(token_id, False);
        deallocate_reg <= tagged Invalid;
    endrule

    rule next_free (initialized && !isValid(next_free_set));
        // $display("Fired next_free");
        let mset <- free_list.allocSet();
        case (mset) matches
            tagged Valid .s: begin
                next_free_set <= tagged Valid s;
            end
            default: begin
                // $display("***** Out of memory at cycle %d, load token validity is %d *****", cycle_count, isValid(load_token));
                next_free_set <= tagged Invalid;
            end
        endcase
    endrule

    rule store_tile (initialized && (isValid(next_free_set) || curr_loc.valid) &&& data_in.first matches tagged Tag_Data {.tt, .st});
        // $display("Fired store_tile");
        data_in.deq;

        // initialization
        let tile = unwrapTile(tt);
        let {new_st, emit_token} = processStopToken(st, rank);

        SET_INDEX set;
        FRAME_INDEX frame; 
        StorageLocation new_loc;
        if (!curr_loc.valid) begin
            set = next_free_set.Valid;
            frame = 0;
            usage_tracker.setFrame(set, 1);
            next_free_set <= tagged Invalid;
            new_loc = StorageLocation { set: set, frame: 1, valid: True };
        end else begin
            set = curr_loc.set;
            frame = curr_loc.frame;
            let full <- usage_tracker.incFrame(set);
            let is_full = full || emit_token;
            new_loc = StorageLocation { set: set, frame: frame + 1, valid: !is_full };
        end
        mem.write(set, frame, TaggedTile { t: tile, st: st });
        curr_loc <= new_loc;

        // update the storage location pointer chain
        if (first_entry.sub(token_counter) matches tagged Invalid) begin
            let p = packLocation(set, frame);
            first_entry.upd(token_counter, tagged Valid p);
            next_table[p] <= tagged Invalid;
            // pmu_id_table[p] <= 0; // TODO: Dynamic pmu ids
            prev_stored <= p;
        end else begin
            let p = packLocation(set, frame);
            next_table[prev_stored] <= tagged Valid p;
            if (prev_stored != p) begin
                next_table[p] <= tagged Invalid;
            end
            prev_stored <= p;
            // pmu_id_table[p] <= 0; // TODO: Dynamic pmu ids
        end

        if (emit_token) begin
            Bit#(32) token_to_emit = zeroExtend(token_counter);
            token_complete.upd(token_counter, True);
            token_out.enq(tagged Tag_Data tuple2(tagged Tag_Ref tuple2(token_to_emit, True), new_st));
            token_counter <= token_counter + 1;
        end
    endrule

    rule start_load_tile (initialized &&& !isValid(load_token) &&& token_in.first matches tagged Tag_Data {.tt, .st});
        // $display("Fired start load tile");
        token_in.deq;
        let token_input = unwrapRef(tt);
        let maybe_packed_loc = first_entry.sub(truncate(token_input.fst));
        if (maybe_packed_loc matches tagged Valid .p) begin
            load_token <= tagged Valid LoadState { loc: p, deallocate: token_input.snd, st: st, orig_token: truncate(token_input.fst) };
        end else begin
            $display("[ERROR]: Token %d not associated with any data", token_input.fst);
            $finish(0);
        end
    endrule

    rule continue_load_tile (initialized &&& load_token matches tagged Valid .load_tk_val &&& !isValid(deallocate_reg));
        // $display("Fired continue load tile");
        let loc = load_tk_val.loc;
        let deallocate = load_tk_val.deallocate;
        let st = load_tk_val.st;
        let orig_token = load_tk_val.orig_token;

        Bool token_is_complete = token_complete.sub(orig_token);
        Bool has_next_piece = isValid(next_table[loc]);

        if (token_is_complete || has_next_piece) begin
            let {set, frame} = unpackLocation(loc);
            read_inflight <= True;
            mem.readReq(set, frame);
            load_meta_q.enq(LoadMeta{ loc: loc, deallocate: deallocate, st: st, orig_token: orig_token });
            // let tile = mem.read(set, frame);
            // let out_rank = tile.st;

            // Check if weve processed all entries for this token
            let next_set = set + 1;
            if (next_table[loc] matches tagged Valid .next_loc) begin
                let {next_set_unpacked, _} = unpackLocation(next_loc); // used to know if weve read every frame in the set
                next_set = next_set_unpacked;
                load_token <= tagged Valid LoadState { loc: next_loc, deallocate: deallocate, st: st, orig_token: orig_token };
            end else begin
                load_token <= tagged Invalid;
                // out_rank = rank + st;
                if (deallocate) begin
                    deallocate_reg <= tagged Valid truncate(orig_token); // used to reset the token_counter head
                end
            end
            
            // data_out.enq(tagged Tag_Data tuple2(tagged Tag_Tile tile.t, out_rank));

            // if (deallocate && set != next_set) begin
            //     free_list.freeSet(set);
            // end
        end
    endrule

    rule retire_read (read_inflight);
        let m <- mem.readRsp;            // TaggedTile {t, st}
        let meta = load_meta_q.first; load_meta_q.deq;
        read_inflight <= False;

        // out_rank mirrors your old logic:
        let out_rank = isValid(next_table[meta.loc]) ? m.st : (rank + meta.st);
        data_out.enq(tagged Tag_Data tuple2(tagged Tag_Tile m.t, out_rank));

        // If you deferred free above, do it here once you know end-of-chain for this token:
        let {set,_} = unpackLocation(meta.loc);
        let next_set = case (next_table[meta.loc]) matches
                        tagged Valid .n: begin let {ns,_} = unpackLocation(n); ns; end
                        default: set + 1;
                        endcase;
        if (meta.deallocate && set != next_set) free_list.freeSet(set);
        endrule

    // ============================================================================
    // End Token and Error Rules
    // ============================================================================

    rule store_tile_end_token (initialized &&& data_in.first matches tagged Tag_EndToken .et);
        $display("End token received in store");
        token_out.enq(tagged Tag_EndToken et);
    endrule

    rule store_tile_error (initialized &&& data_in.first matches tagged Tag_Instruction .ip);
        $display("[ERROR]: Instruction received in data input"); // TODO: Should be able to accept incoming config
        $finish(0);
    endrule

    rule start_load_tile_error (initialized &&& token_in.first matches tagged Tag_Instruction .ip);
        $display("[ERROR]: Instruction received in token input");
        $finish(0);
    endrule

    rule start_load_tile_end_token (initialized &&& !isValid(load_token) &&& token_in.first matches tagged Tag_EndToken .et &&& !read_inflight);
        // Print state of memory at end of stream
        for (Integer i = 0; i < valueOf(SETS); i = i + 1) begin
            if (!free_list.isSetFree(fromInteger(i))) begin
                $display("[MEMORY USAGE]: Set %d: %d frames used", i, usage_tracker.getCount(fromInteger(i)));
            end else begin
                $display("[MEMORY USAGE]: Set %d: No frames used", i);
            end
        end
        data_out.enq(tagged Tag_EndToken et);
    endrule

    // ============================================================================
    // Initialization and Cycle Counting Rules
    // ============================================================================

    rule initialization (!initialized);
        first_entry.upd(first_entry_initialized_index, tagged Invalid);
        token_complete.upd(first_entry_initialized_index, False);
        if (first_entry_initialized_index == fromInteger(valueOf(MAX_ENTRIES) - 1)) begin
            initialized <= True; 
        end else begin
            first_entry_initialized_index <= first_entry_initialized_index + 1;
        end
    endrule

    rule cycle_counter (initialized);
        cycle_count <= cycle_count + 1;
    endrule

    // ============================================================================
    // Methods
    // ============================================================================

    method Action put_data(ChannelMessage msg);
        data_in.enq(msg);
    endmethod
    method ActionValue#(ChannelMessage) get_token();
        let msg = token_out.first;
        token_out.deq;
        return msg;
    endmethod
    method Action put_token(ChannelMessage msg);
        token_in.enq(msg);
    endmethod
    method ActionValue#(ChannelMessage) get_data();
        let msg = data_out.first;
        data_out.deq;
        return msg;
    endmethod
    method Int#(32) get_cycle_count();
        return unpack(cycle_count);
    endmethod

    interface Operation_IFC operation;
        method Action put(Int#(32) i, ChannelMessage msg); // i = 0 for data, 1 for token
            if (i == 0) begin
                data_in.enq(msg);
            end else begin
                token_in.enq(msg);
            end
        endmethod

        method ActionValue#(ChannelMessage) get(Int#(32) i); // i = 0 for token, 1 for data
            ChannelMessage msg;
            if (i == 0) begin
                msg = token_out.first;
                token_out.deq;
            end else begin
                msg = data_out.first;
                data_out.deq;
            end
            return msg;
        endmethod
    endinterface

endmodule

endpackage