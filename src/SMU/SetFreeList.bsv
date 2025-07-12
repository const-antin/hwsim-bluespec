package SetFreeList;

import Vector::*;
import Types::*;
import Parameters::*;

interface SetFreeList_IFC;
    method ActionValue#(Maybe#(SETS_LOG)) allocSet();
    method Action freeSet(SETS_LOG s);
    method Bool isSetFree(SETS_LOG s);
endinterface

module mkSetFreeList(SetFreeList_IFC);
    Reg#(Bit#(SETS)) free_sets <- mkReg(0);  // All sets initially free (0 = free, 1 = used)

    // Simple priority encoder
    function Maybe#(SETS_LOG) findFree(Bit#(SETS) bitmap);
        Maybe#(SETS_LOG) result = Invalid;
        for (Integer i = 0; i < valueOf(SETS); i = i + 1)
            if (bitmap[i] == 0)
                result = tagged Valid fromInteger(i);
        return result;
    endfunction

    method ActionValue#(Maybe#(SETS_LOG)) allocSet();
        actionvalue
            let result = findFree(free_sets);
            if (result matches tagged Valid .idx)
                free_sets <= free_sets | (1 << pack(idx));  // Mark as used (set bit to 1)
            return result;
        endactionvalue
    endmethod

    method Action freeSet(SETS_LOG s);
        free_sets <= free_sets & ~(1 << pack(s));  // Clear the bit to mark as free
    endmethod

    method Bool isSetFree(SETS_LOG s);
        return free_sets[pack(s)] == 0;
    endmethod

endmodule

endpackage
