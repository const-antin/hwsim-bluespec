// TODO: Make everything work in fifo order. I think this should immediately work as long as I emit the token earlier. 
    // I already have the logic necessary to make sure i don't read data that hasn't been stored (untested)

// TODO: Replace loop with find
// TODO: Remove memory size dependency on tile size, should just have banks be as large as possible
// TODO: Swap registers for SRAM
// TODO: rank shouldn't be a parameter, should be stored in a reg and parsed from a config input

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
    
    // Only internal state needed is the storage FIFO and token counter
    BankedMemory_IFC mem <- mkBankedMemory;
    SetFreeList_IFC free_list <- mkSetFreeList;
    SetUsageTracker_IFC usage_tracker <- mkSetUsageTracker;
    Reg#(StorageLocation) curr_loc <- mkReg(StorageLocation { set: 0, frame: 0, valid: False });
    ConfigReg#(Bit#(TLog#(MAX_ENTRIES))) token_counter <- mkConfigReg(0);
    Reg#(Bit#(32)) cycle_count <- mkReg(0);

    RegFile#(Bit#(TLog#(MAX_ENTRIES)), Maybe#(Bit#(TLog#(MAX_ENTRIES)))) first_entry <- mkRegFileWCF(0, fromInteger(valueOf(MAX_ENTRIES) - 1));    
    RegFile#(Bit#(TLog#(MAX_ENTRIES)), Bool) token_complete <- mkRegFileWCF(0, fromInteger(valueOf(MAX_ENTRIES) - 1));
    Vector#(MAX_ENTRIES, ConfigReg#(Maybe#(Bit#(TLog#(MAX_ENTRIES))))) next_table <- replicateM(mkConfigReg(tagged Invalid));
    // Vector#(MAX_ENTRIES, ConfigReg#(Bit#(TLog#(MAX_ENTRIES)))) pmu_id_table <- replicateM(mkConfigReg(0)); // TODO: Unused for static
    Reg#(Bit#(TLog#(MAX_ENTRIES))) prev_stored <- mkReg(0);

    let frame_width = valueOf(TLog#(FRAMES_PER_SET));
    let set_width = valueOf(TLog#(SETS));
    Reg#(Maybe#(Tuple4#(Bit#(TLog#(MAX_ENTRIES)), Bool, StopToken, Bit#(TLog#(MAX_ENTRIES))))) load_token <- mkReg(tagged Invalid);

    Reg#(Bool) initialized <- mkReg(False);
    Reg#(Bit#(TLog#(MAX_ENTRIES))) first_entry_initialized_index <- mkReg(0);

    ConfigReg#(Maybe#(SET_INDEX)) next_free_set <- mkConfigReg(tagged Invalid);
    ConfigReg#(Maybe#(Bit#(TLog#(MAX_ENTRIES)))) deallocate_reg <- mkConfigReg(tagged Invalid);

    // ============================================================================
    // Rule Orderings
    // ============================================================================

    (* execution_order = "cycle_counter, store_tile, next_free, continue_load_tile" *)
    (* execution_order = "cycle_counter, start_load_tile" *)
    (* descending_urgency = "deallocate_token, store_tile" *)

    // ============================================================================
    // Main Logic Rules
    // ============================================================================

    rule deallocate_token (initialized &&& isValid(deallocate_reg));
        first_entry.upd(deallocate_reg.Valid, tagged Invalid);
        token_complete.upd(deallocate_reg.Valid, False);
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
        let new_st = st;
        let emit_token = False;
        if (st >= rank) begin
            new_st = st - rank;
            emit_token = True;
        end
        StorageLocation new_loc;
        let set = 0;
        let frame = 0;

        // store the tile, update the next storage location
        if (!curr_loc.valid) begin
            set = next_free_set.Valid;
            frame = 0;
            mem.write(set, 0, TaggedTile { t: tile, st: st });
            usage_tracker.setFrame(set, 1);
            new_loc = StorageLocation { set: set, frame: 1, valid: True };
            next_free_set <= tagged Invalid;
        end else begin
            set = curr_loc.set;
            frame = curr_loc.frame;
            mem.write(set, frame, TaggedTile { t: tile, st: st });
            let full <- usage_tracker.incFrame(set);
            full = full || emit_token;
            new_loc = StorageLocation { set: set, frame: frame + 1, valid: !full };
        end
        curr_loc <= new_loc;

        // update the storage location pointer chain
        if (first_entry.sub(token_counter) matches tagged Invalid) begin
            let p = pack({set, frame});
            first_entry.upd(token_counter, tagged Valid p);
            next_table[p] <= tagged Invalid;
            // pmu_id_table[p] <= 0; // TODO: Dynamic pmu ids
            prev_stored <= p;
        end else begin
            let p = pack({set, frame});
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
            load_token <= tagged Valid tuple4(p, token_input.snd, st, truncate(token_input.fst)); // (<set, frame>, deallocate, st, orig_token)
        end else begin
            $display("[ERROR]: Token %d not associated with any data", token_input.fst);
            $finish(0);
        end
    endrule

    rule continue_load_tile (initialized &&& load_token matches tagged Valid .load_tk_val &&& !isValid(deallocate_reg));
        // $display("Fired continue load tile");
        let loc_table_entry = tpl_1(load_tk_val); // {set, frame}
        let deallocate = tpl_2(load_tk_val);
        let st = tpl_3(load_tk_val);
        let orig_token = tpl_4(load_tk_val);

        Bool token_is_complete = token_complete.sub(orig_token);
        Bool has_next_piece = isValid(next_table[loc_table_entry]);

        if (token_is_complete || has_next_piece) begin
            SET_INDEX set   = truncate(loc_table_entry >> valueOf(TLog#(FRAMES_PER_SET)));
            FRAME_INDEX frame = truncate(loc_table_entry);
            let tile = mem.read(set, frame);
            let out_rank = tile.st;

            // Check if weve processed all entries for this token
            let next_set = set + 1;
            if (next_table[loc_table_entry] matches tagged Valid .next_loc) begin
                next_set = truncate(next_loc >> valueOf(TLog#(FRAMES_PER_SET))); // used to know if we've read every frame in the set
                load_token <= tagged Valid tuple4(next_loc, deallocate, st, orig_token);
            end else begin
                load_token <= tagged Invalid;
                out_rank = rank + st;
                if (deallocate) begin
                    deallocate_reg <= tagged Valid truncate(orig_token); // used to reset the token_counter head
                end
            end
            
            data_out.enq(tagged Tag_Data tuple2(tagged Tag_Tile tile.t, out_rank));

            if (deallocate) begin
                if (set != next_set) begin
                    free_list.freeSet(set); 
                end 
            end
        end
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

    rule start_load_tile_end_token (initialized &&& !isValid(load_token) &&& token_in.first matches tagged Tag_EndToken .et);
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
        // $display("-------------------------------------------");
        // $display("[CYCLE COUNTER]: %d", cycle_count);
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