package PMU;

import FIFO::*;
import Types::*;
import Vector::*;
import RegFile::*;
import BankedMemory::*;
import Parameters::*;
import SetFreeList::*;
import SetUsageTracker::*;

// Tracking the current storage location
typedef struct {
    SETS_LOG set;
    FRAMES_PER_SET_LOG frame;
    Bool valid;
} StorageLocation deriving(Bits, Eq);

// A struct to hold a value and its associated token
typedef struct {
    TaggedTile value;
    Int#(32) token;
} ValueToken deriving(Bits, Eq);

typedef Bit#(TAdd#(TLog#(SETS), TLog#(FRAMES_PER_SET))) TokenBits;

// Interface that just exposes the modules existence
// (since all communication is through the FIFOs passed as parameters)
interface PMU_IFC;
endinterface

// PMU module that processes between the FIFOs
module mkPMU#(
    FIFO#(TaggedTile) data_in,      // Values come in here
    FIFO#(Int#(32)) token_out,    // Generated tokens go out here
    FIFO#(Int#(32)) token_in,     // Tokens come back in here
    FIFO#(TaggedTile) data_out      // Retrieved values go out here
)(PMU_IFC);
    
    // Only internal state needed is the storage FIFO and token counter
    BankedMemory_IFC mem <- mkBankedMemory;
    SetFreeList_IFC free_list <- mkSetFreeList;
    SetUsageTracker_IFC usage_tracker <- mkSetUsageTracker;
    Reg#(StorageLocation) curr_loc <- mkReg(StorageLocation { set: 0, frame: 0, valid: False });

    rule store_tile;
        let tile = data_in.first;
        data_in.deq;

        StorageLocation new_loc = curr_loc;
        Int#(32) token = 0;

        if (!curr_loc.valid) begin
            let mset <- free_list.allocSet();
            case (mset) matches
                tagged Valid .set: begin
                    mem.write(set, 0, tile);
                    usage_tracker.setFrame(set, 1);

                    FRAMES_PER_SET_LOG zero_frame = 0;
                    token = zeroExtend(unpack({ pack(set), pack(zero_frame) }));
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

            mem.write(set, frame, tile);
            let full <- usage_tracker.incFrame(set);

            token = zeroExtend(unpack({ pack(set), pack(frame) }));
            new_loc = StorageLocation {
                set: set,
                frame: frame + 1,
                valid: !full
            };
        end

        token_out.enq(token);
        curr_loc <= new_loc;
        $display("[STORE] curr_loc set = %0d, (frame + 1) = %0d, valid = %0d", new_loc.set, new_loc.frame, new_loc.valid);
    endrule


    // Rule to handle token retrievals: find matching value and return it
    rule load_tile;
        let token = token_in.first;
        token_in.deq;
        
        let token_bits = pack(token);        // Int#(32) -> Bit#(32)
        let frame_width = valueOf(TLog#(FRAMES_PER_SET));
        let set_width = valueOf(TLog#(SETS));
        SETS_LOG set = token_bits[frame_width + set_width - 1 : frame_width];
        FRAMES_PER_SET_LOG frame = token_bits[frame_width - 1 : 0];

        let tile = mem.read(set, frame);
        data_out.enq(tile);
    endrule

endmodule

endpackage