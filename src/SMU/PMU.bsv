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

// Tracking the current storage location
typedef struct {
    SET_INDEX set;
    FRAME_INDEX frame;
    Bool valid;
} StorageLocation deriving(Bits, Eq);

typedef struct {
  Vector#(MAX_ENTRIES, StorageLocation) vec;
  UInt#(TLog#(MAX_ENTRIES)) next_idx;
} TokenMapping deriving (Bits, Eq);
typedef UInt#(TAdd#(TLog#(SETS), TLog#(FRAMES_PER_SET))) StorageAddr;

interface Operation_IFC;
    method Action put(Int#(32) input_port, ChannelMessage msg);
    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
endinterface

// Interface that just exposes the modules existence
interface PMU_IFC;
    interface Operation_IFC operation;
    
    method Action put_data(ChannelMessage msg);
    method ActionValue#(ChannelMessage) get_token();
    method Action put_token(ChannelMessage msg);
    method ActionValue#(ChannelMessage) get_data();
    method Bool ready();
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
    Vector#(MAX_ENTRIES, ConfigReg#(UInt#(TLog#(MAX_ENTRIES)))) next_idx_table <- replicateM(mkConfigReg(unpack(0)));
    Vector#(MAX_ENTRIES, RegFile#(StorageAddr, Bit#(SizeOf#(StorageLocation)))) token_storage <- replicateM(mkRegFileWCF(0, fromInteger(valueOf(TMul#(FRAMES_PER_SET, SETS)) - 1)));

    let frame_width = valueOf(TLog#(FRAMES_PER_SET));
    let set_width = valueOf(TLog#(SETS));
    Reg#(Maybe#(Tuple2#(Bit#(32), Bool))) load_token <- mkReg(tagged Invalid);
    Reg#(UInt#(TLog#(MAX_ENTRIES))) load_idx <- mkReg(0);

    Reg#(Int#(32)) loaded_from_set <- mkReg(0);

    rule cycle_counter;
        $display("[CYCLE COUNTER]: %d", cycle_count);
        cycle_count <= cycle_count + 1;
    endrule

    rule store_tile;
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
                StorageLocation storage_location = curr_loc;

                if (!curr_loc.valid) begin
                    let mset <- free_list.allocSet();
                    case (mset) matches
                        tagged Valid .set: begin
                            mem.write(set, 0, TaggedTile { t: tile, st: st });
                            usage_tracker.setFrame(set, 1);

                            FRAME_INDEX zero_frame = 0;
                            storage_location = StorageLocation { set: set, frame: 0, valid: True };
                            new_loc = StorageLocation { set: set, frame: 1, valid: True };
                        end
                        default: begin
                            $display("***** Out of memory *****");
                            $finish;
                        end
                    endcase
                end else begin
                    let set = curr_loc.set;
                    let frame = curr_loc.frame;
                    storage_location = curr_loc;

                    mem.write(set, frame, TaggedTile { t: tile, st: st });
                    let full <- usage_tracker.incFrame(set);

                    new_loc = StorageLocation {
                        set: set,
                        frame: frame + 1,
                        valid: !full
                    };
                end

                let idx = next_idx_table[token_counter];
                token_storage[token_counter].upd(zeroExtend(idx), pack(storage_location));
                next_idx_table[token_counter] <= idx + 1;

                if (emit_token) begin
                    Bit#(32) token_to_emit = zeroExtend(token_counter);
                    token_counter <= token_counter + 1;
                    token_out.enq(tagged Tag_Data tuple2(tagged Tag_Ref tuple2(token_to_emit, False), new_st));
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
                load_token <= tagged Valid token_input;
                load_idx <= 0;
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
        $display("[DEBUG]: Continuing load tile %d, %d", fromMaybe(tuple2(0, False), load_token).fst, fromMaybe(tuple2(0, False), load_token).snd);
        UInt#(TLog#(MAX_ENTRIES)) token_idx = truncate(unpack(fromMaybe(tuple2(0, False), load_token).fst));
        let tm = token_storage[token_idx];
        let deallocate = fromMaybe(tuple2(0, False), load_token).snd;
        if (load_idx < next_idx_table[token_idx]) begin
            let loc = unpack(tm.sub(zeroExtend(load_idx)));
            let set = loc.set;
            let frame = loc.frame;
            let tile = mem.read(set, frame);
            data_out.enq(tagged Tag_Data tuple2(tagged Tag_Tile tile.t, tile.st));
            if (deallocate) begin
                let set_count = usage_tracker.getCount(set);
                if (set_count - 1 == unpack(pack(loaded_from_set))) begin
                    loaded_from_set <= 0;
                    free_list.freeSet(set); 
                end else begin
                    loaded_from_set <= loaded_from_set + 1;
                end
            end
            if (load_idx == next_idx_table[token_idx] - 1) begin
                load_token <= tagged Invalid;
                load_idx <= 0;
            end else begin
                load_idx <= load_idx + 1;
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
    // method Bool ready();
    //     return token_table_initialized;
    // endmethod

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