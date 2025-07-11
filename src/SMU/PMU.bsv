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
    SetIdx set;
    FrameIdx frame;
    Bool valid;
} StorageLocation deriving(Bits, Eq);

// A struct to hold a value and its associated token
typedef struct {
    TaggedTile value;
    Int#(32) token;
} ValueToken deriving(Bits, Eq);

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
        Bit#(10) token_bits = 0;
        Int#(32) token = 0;
        SetIdx set;

        if (!curr_loc.valid) begin
            let mset <- free_list.allocSet();
            case (mset) matches
                tagged Valid .s: begin
                    set = s;
                    mem.write(set, 0, tile);
                    usage_tracker.incFrame(set);

                    token_bits = { pack(set), 3'b000 };
                    new_loc = StorageLocation { set: set, frame: 1, valid: True };
                end
                default: begin
                    $display("***** Out of memory *****");
                    $finish;
                end
            endcase
        end else begin
            set = curr_loc.set;
            let frame = curr_loc.frame;

            mem.write(set, frame, tile);
            usage_tracker.incFrame(set);

            token_bits = { pack(set), pack(frame) };
            let full = usage_tracker.isFull(set);
            new_loc = StorageLocation {
                set: set,
                frame: frame + 1,
                valid: !full
            };
        end

        token = signExtend(unpack(token_bits));
        token_out.enq(token);
        curr_loc <= new_loc;
    endrule


    // Rule to handle token retrievals: find matching value and return it
    rule load_tile;
        let token = token_in.first;
        token_in.deq;
        
        let token_bits = pack(token);        // Int#(32) -> Bit#(32)
        SetIdx   set   = truncateLSB(token_bits); // token_bits[9:3]
        FrameIdx frame = truncate(token_bits);    // token_bits[2:0]

        let tile = mem.read(set, frame);
        data_out.enq(tile);
    endrule

endmodule

endpackage