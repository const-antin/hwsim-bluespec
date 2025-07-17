package SetUsageTracker;

import Vector::*;
import Types::*;
import ConfigReg::*;
import Parameters::*;

interface SetUsageTracker_IFC;
    method ActionValue#(Bool) incFrame(SETS_LOG s); // returns True if the set is full after incrementing
    method Action setFrame(SETS_LOG s, UInt#(32) count);
    method UInt#(32) getCount(SETS_LOG s);
endinterface

module mkSetUsageTracker(SetUsageTracker_IFC);
    Vector#(SETS, ConfigReg#(UInt#(32))) usage <- replicateM(mkConfigReg(0));

    method ActionValue#(Bool) incFrame(SETS_LOG s);
        let count = usage[s];
        let new_count = count + 1;
        usage[s] <= new_count;
        return count + 1 == fromInteger(valueOf(FRAMES_PER_SET));
    endmethod

    method Action setFrame(SETS_LOG s, UInt#(32) count);
        usage[s] <= count;
    endmethod

    method UInt#(32) getCount(SETS_LOG s);
        return usage[s];
    endmethod

endmodule

endpackage
