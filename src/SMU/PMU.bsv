package PMU;

import FIFO::*;
import FIFOF::*;
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

// Tracking the current storage location
typedef struct {
    SET_INDEX set;
    FRAME_INDEX frame;
    Bool valid;
} StorageLocation deriving(Bits, Eq);

typedef UInt#(TAdd#(TLog#(SETS), TLog#(FRAMES_PER_SET))) StorageAddr;

// Interface that just exposes the modules existence
interface PMU_IFC;
    interface Operation_IFC operation;
    
    method Action put_data(ChannelMessage msg);
    method ActionValue#(ChannelMessage) get_token();
    method Action put_token(ChannelMessage msg);
    method ActionValue#(ChannelMessage) get_data();
endinterface


// PMU module that processes between the FIFOs
module mkPMU#(
    Int#(32) rank_in                    // Rank of the current tile
)(PMU_IFC);
    FIFO#(ChannelMessage) data_in <- mkFIFO;      // Values come in here
    FIFO#(ChannelMessage) token_out <- mkFIFO;    // Generated tokens go out here
    FIFO#(ChannelMessage) token_in <- mkFIFO;     // Tokens come back in here
    FIFO#(ChannelMessage) data_out <- mkFIFO;     // Retrieved values go out here
    
    // Only internal state needed is the storage FIFO and token counter
    BankedMemory_IFC mem <- mkBankedMemory;
    SetFreeList_IFC free_list <- mkSetFreeList;
    SetUsageTracker_IFC usage_tracker <- mkSetUsageTracker;
    Reg#(StorageLocation) curr_loc <- mkReg(StorageLocation { set: 0, frame: 0, valid: False });
    Reg#(Int#(32)) rank <- mkReg(rank_in);
    Reg#(Bit#(TLog#(MAX_ENTRIES))) token_counter <- mkReg(0);
    Reg#(Bit#(32)) cycle_count <- mkReg(0);

    RegFile#(Bit#(TLog#(MAX_ENTRIES)), Maybe#(Bit#(TLog#(MAX_ENTRIES)))) first_entry <- mkRegFileWCF(0, fromInteger(valueOf(MAX_ENTRIES) - 1));    
    Vector#(MAX_ENTRIES, ConfigReg#(Maybe#(Bit#(TLog#(MAX_ENTRIES))))) next_table <- replicateM(mkConfigReg(tagged Invalid));
    // Vector#(MAX_ENTRIES, ConfigReg#(Bit#(TLog#(MAX_ENTRIES)))) pmu_id_table <- replicateM(mkConfigReg(0)); // TODO: Unused for static
    Reg#(Bit#(TLog#(MAX_ENTRIES))) prev_stored <- mkReg(0);

    let frame_width = valueOf(TLog#(FRAMES_PER_SET));
    let set_width = valueOf(TLog#(SETS));
    Reg#(Maybe#(Tuple3#(Bit#(TLog#(MAX_ENTRIES)), Bool, StopToken))) load_token <- mkReg(tagged Invalid);

    Reg#(Bool) initialized <- mkReg(False);
    Reg#(Bit#(TLog#(MAX_ENTRIES))) first_entry_initialized_index <- mkReg(0);

    ConfigReg#(Maybe#(SET_INDEX)) next_free_set <- mkConfigReg(tagged Invalid);

    rule initialization (!initialized);
        first_entry.upd(first_entry_initialized_index, tagged Invalid);
        if (first_entry_initialized_index == fromInteger(valueOf(MAX_ENTRIES) - 1)) begin
            initialized <= True; 
        end else begin
            first_entry_initialized_index <= first_entry_initialized_index + 1;
        end
    endrule

    rule cycle_counter (initialized);
        // $display("[CYCLE COUNTER]: %d", cycle_count);
        cycle_count <= cycle_count + 1;
    endrule

    (* execution_order = "store_tile, next_free" *)
    rule next_free (initialized && !isValid(next_free_set));
        let mset <- free_list.allocSet();
        case (mset) matches
            tagged Valid .s: begin
                next_free_set <= tagged Valid s;
            end
            default: begin
                if (cycle_count % 1000 == 0) begin
                    $display("***** Out of memory at cycle %d, load token validity is %d *****", cycle_count, isValid(load_token));
                end
                next_free_set <= tagged Invalid;
            end
        endcase
    endrule

    rule store_tile (initialized && (isValid(next_free_set) || curr_loc.valid));
        $display("[DEBUG]: Storing tile at cycle %d", cycle_count);
        let d_in = data_in.first;
        data_in.deq;

        case (d_in) matches
            tagged Tag_Data {.tt, .st}: begin
                let tile = unwrapTile(tt);
                let new_st = st;
                let emit_token = False;
                if (st >= rank) begin
                    new_st = st - rank;
                    emit_token = True;
                end

                StorageLocation new_loc = curr_loc;

                let set = 0;
                let frame = 0;

                if (!curr_loc.valid) begin
                    set = next_free_set.Valid;
                    frame = 0;
                    mem.write(set, 0, TaggedTile { t: tile, st: st });
                    usage_tracker.setFrame(set, 1);
                    new_loc = StorageLocation { set: set, frame: 1, valid: True };
                    next_free_set <= tagged Invalid;
                    $display("[DEBUG]: !curr_loc.valid: tile in set %d, frame %d", set, frame);
                end else begin
                    $display("[DEBUG]: Storing tile in set %d, frame %d", curr_loc.set, curr_loc.frame);
                    set = curr_loc.set;
                    frame = curr_loc.frame;

                    mem.write(set, frame, TaggedTile { t: tile, st: st });
                    let full <- usage_tracker.incFrame(set);
                    $display("[DEBUG]: full before: %d", full);
                    full = full || emit_token;
                    $display("[DEBUG]: full: %d", full);

                    new_loc = StorageLocation {
                        set: set,
                        frame: frame + 1,
                        valid: !full
                    };
                end

                if (first_entry.sub(token_counter) matches tagged Invalid) begin
                    let p = pack({set, frame});
                    first_entry.upd(token_counter, tagged Valid p);
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
                    token_counter <= token_counter + 1;
                    token_out.enq(tagged Tag_Data tuple2(tagged Tag_Ref tuple2(token_to_emit, True), new_st));
                end
                curr_loc <= new_loc;
            end
            tagged Tag_Instruction .ip: begin
                $display("[ERROR]: Instruction received in data input"); // TODO: Should be able to accept incoming config
                $finish(0);
            end
            tagged Tag_EndToken .et: begin
                token_out.enq(tagged Tag_EndToken et);
                $display("End token received in store");
            end
        endcase
    endrule

    // Rule to handle token retrievals: find matching value and return it
    rule start_load_tile (!isValid(load_token));
        let token_msg = token_in.first;
        token_in.deq;
        
        case (token_msg) matches
            tagged Tag_Data {.tt, .st}: begin
                let token_input = unwrapRef(tt);
                let maybe_packed_loc = first_entry.sub(truncate(token_input.fst));
                if (maybe_packed_loc matches tagged Valid .p) begin
                    load_token <= tagged Valid tuple3(p, token_input.snd, st);
                    $display("[DEBUG]: starting load tile at cycle %d, load_token %d", cycle_count, tpl_1(load_token.Valid));
                end else begin
                    $display("[ERROR]: No valid location found for token %d", token_input.fst);
                    $finish(0);
                end
            end
            tagged Tag_EndToken .et: begin
                // Print the state of the memory being used
                for (Integer i = 0; i < valueOf(SETS); i = i + 1) begin
                    // Check if set is valid
                    if (!free_list.isSetFree(fromInteger(i))) begin
                        $display("[MEMORY USAGE]: Set %d: %d frames used", i, usage_tracker.getCount(fromInteger(i)));
                    end else begin
                        $display("[MEMORY USAGE]: Set %d: No frames used", i);
                    end
                end
                data_out.enq(tagged Tag_EndToken et);
                $display("End token received");
            end
            default: begin
                $display("[ERROR]: Expected data message with token");
                $finish(0);
            end
        endcase
    endrule

    rule continue_load_tile (isValid(load_token));
        let loc_table_entry = tpl_1(load_token.Valid); // {set, frame}
        let deallocate = tpl_2(load_token.Valid);
        let st = tpl_3(load_token.Valid);
        SET_INDEX set   = truncate(loc_table_entry >> valueOf(TLog#(FRAMES_PER_SET)));
        FRAME_INDEX frame = truncate(loc_table_entry);
        let tile = mem.read(set, frame);
        let out_rank = tile.st;

        // Check if weve processed all entries for this token
        let next_set = set + 1;
        if (next_table[loc_table_entry] matches tagged Valid .next_loc) begin
            next_set = truncate(next_loc >> valueOf(TLog#(FRAMES_PER_SET)));
            load_token <= tagged Valid tuple3(next_loc, deallocate, st);
        end else begin
            load_token <= tagged Invalid;
            out_rank = rank + st;
        end
        
        $display("[DEBUG]: Cycle %d: Continuing load tile set %d, next_set %d, frame %d, deallocate: %d, out_rank %d", cycle_count, set, next_set, frame, deallocate, out_rank);      
        data_out.enq(tagged Tag_Data tuple2(tagged Tag_Tile tile.t, out_rank));

        if (deallocate) begin
            if (set != next_set) begin
                free_list.freeSet(set); 
                $display("[DEBUG]: Freed set %d", set);
            end 
        end
    endrule

    method Action put_data(ChannelMessage msg);
        data_in.enq(msg);
    endmethod
    method ActionValue#(ChannelMessage) get_token();
        token_out.deq;
        return token_out.first;
    endmethod
    method Action put_token(ChannelMessage msg);
        token_in.enq(msg);
    endmethod
    method ActionValue#(ChannelMessage) get_data();
        data_out.deq;
        return data_out.first;
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
                token_out.deq;
                msg = token_out.first;
            end else begin
                data_out.deq;
                msg = data_out.first;
            end
            return msg;
        endmethod
    endinterface

endmodule

endpackage