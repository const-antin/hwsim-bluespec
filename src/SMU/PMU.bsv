package PMU;

import FIFO::*;
import Types::*;
import Vector::*;
import RegFile::*;
import BankedMemory::*;

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
    Reg#(Int#(32)) tokenCounter <- mkReg(0);
    BankedMemory_IFC mem <- mkBankedMemory;

    // Rule to handle incoming values: generate token and store value-token pair
    rule store_tile;
        let tile = data_in.first;
        data_in.deq;
        let token = tokenCounter;
        tokenCounter <= tokenCounter + 1;
        let token_bits = pack(token);
        SetIdx   set   = truncateLSB(token_bits);          // top 7 bits
        FrameIdx frame = truncate(token_bits);             // lower 3 bits
        mem.write(set, frame, tile);
        token_out.enq(token);
    endrule

    // Rule to handle token retrievals: find matching value and return it
    rule load_tile;
        let token = token_in.first;
        token_in.deq;
        
        let token_bits = pack(token);
        SetIdx   set   = truncateLSB(token_bits);
        FrameIdx frame = truncate(token_bits);

        let tile = mem.read(set, frame);
        data_out.enq(tile);
    endrule

endmodule

endpackage