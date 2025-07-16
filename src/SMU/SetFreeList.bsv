package SetFreeList;

import Vector::*;
import Types::*;
import Parameters::*;

interface SetFreeList_IFC;
    method ActionValue#(Maybe#(SETS_LOG)) allocSet(Maybe#(SETS_LOG) exclude);
    method Action freeSet(SETS_LOG s);
    method Bool isSetFree(SETS_LOG s);
endinterface

module mkSetFreeList(SetFreeList_IFC);
    Vector#(SETS, Reg#(Bool)) free_sets <- replicateM(mkReg(True));  // All sets initially free (true = free, false = used)

    method ActionValue#(Maybe#(SETS_LOG)) allocSet(Bit#(SETS) exclude);
        actionvalue
            Maybe#(SETS_LOG) result = Invalid;
            for (Integer i = 0; i < valueOf(SETS); i = i + 1) begin
                if (!isValid(result) && (exclude[i] == 0) && free_sets[i]) begin
                    free_sets[i] <= False;
                    result = tagged Valid fromInteger(i);
                end
            end
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
