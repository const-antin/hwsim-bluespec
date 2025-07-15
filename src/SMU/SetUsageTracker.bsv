package SetUsageTracker;

import Vector::*;
import Types::*;
import Parameters::*;

interface SetUsageTracker_IFC;
    method ActionValue#(Bool) incFrame(SETS_LOG s); // returns True if the set is full after incrementing
    method ActionValue#(Bool) decFrame(SETS_LOG s); // returns True if the set is empty after decrementing  
    method Action setFrame(SETS_LOG s, UInt#(32) count);
    method ActionValue#(UInt#(32)) getCount(SETS_LOG s);
endinterface

module mkSetUsageTracker(SetUsageTracker_IFC);
    Vector#(SETS, Reg#(UInt#(32))) usage <- replicateM(mkReg(0));

    method ActionValue#(Bool) incFrame(SETS_LOG s);
        let count = usage[s];
        let new_count = count + 1;
        usage[s] <= new_count;
        return count + 1 == fromInteger(valueOf(FRAMES_PER_SET));
    endmethod

    method ActionValue#(Bool) decFrame(SETS_LOG s);
        let count = usage[s];
        if (count > 0)
            usage[s] <= count - 1;
        return count - 1 == 0;
    endmethod

    method Action setFrame(SETS_LOG s, UInt#(32) count);
        usage[s] <= count;
    endmethod

    method ActionValue#(UInt#(32)) getCount(SETS_LOG s);
        return usage[s];
    endmethod

endmodule

endpackage
