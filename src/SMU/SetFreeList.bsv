package SetFreeList;

import Vector::*;
import Types::*;
import Parameters::*;

// Type alias
typedef Bit#(TLog#(SETS)) SetIdx;  // e.g., 7-bit index for 128 sets

interface SetFreeList_IFC;
    method ActionValue#(Maybe#(SetIdx)) allocSet();
    method Action freeSet(SetIdx s);
endinterface

module mkSetFreeList(SetFreeList_IFC);
    Reg#(Bit#(SETS)) free_sets <- mkReg(maxBound);  // All sets initially free

    // Simple priority encoder
    function Maybe#(SetIdx) findFree(Bit#(128) bitmap);
        Maybe#(SetIdx) result = Invalid;
        for (Integer i = 0; i < 128; i = i + 1)
            if (bitmap[i] == 1)
                result = tagged Valid fromInteger(i);
        return result;
    endfunction

    method ActionValue#(Maybe#(SetIdx)) allocSet();
        actionvalue
            let result = findFree(free_sets);
            if (result matches tagged Valid .idx)
                free_sets <= free_sets & ~(1 << pack(idx));  // Mark as used
            return result;
        endactionvalue
    endmethod

    method Action freeSet(SetIdx s);
        free_sets <= free_sets | (1 << pack(s));  // Mark as free
    endmethod

endmodule

endpackage
