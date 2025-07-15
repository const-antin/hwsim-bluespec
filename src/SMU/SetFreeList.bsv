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
    Vector#(SETS, Reg#(Bool)) free_sets <- replicateM(mkReg(True));  // All sets initially free (true = free, false = used)

    // Simple priority encoder
    function Maybe#(SETS_LOG) findFree(Vector#(SETS, Reg#(Bool)) free_sets);
        Maybe#(SETS_LOG) result = Invalid;
        for (Integer i = 0; i < valueOf(SETS); i = i + 1)
            if (free_sets[i])
                result = tagged Valid fromInteger(i);
        return result;
    endfunction

    method ActionValue#(Maybe#(SETS_LOG)) allocSet();
        actionvalue
            let result = findFree(free_sets);
            if (result matches tagged Valid .idx)
                free_sets[idx] <= False;  // Mark as used 
            return result;
        endactionvalue
    endmethod

    method Action freeSet(SETS_LOG s);
        free_sets[s] <= True;  
    endmethod

    method Bool isSetFree(SETS_LOG s);
        return free_sets[s];
    endmethod

endmodule

endpackage
