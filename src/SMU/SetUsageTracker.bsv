package SetUsageTracker;

import RegFile::*;
import Types::*;
import Parameters::*;

interface SetUsageTracker_IFC;
    method ActionValue#(Bool) incFrame(SETS_LOG s); // returns True if the set is full after incrementing
    method ActionValue#(Bool) decFrame(SETS_LOG s); // returns True if the set is empty after decrementing  
    method Action setFrame(SETS_LOG s, UInt#(32) count);
    method UInt#(32) getCount(SETS_LOG s);
endinterface

module mkSetUsageTracker(SetUsageTracker_IFC);
    RegFile#(SETS_LOG, UInt#(32)) usage <- mkRegFile(0, fromInteger(valueOf(SETS) - 1));


    method ActionValue#(Bool) incFrame(SETS_LOG s);
        let count = usage.sub(s);
        let new_count = count + 1;
        usage.upd(s, new_count);
        return count + 1 == fromInteger(valueOf(FRAMES_PER_SET));
    endmethod

    method ActionValue#(Bool) decFrame(SETS_LOG s);
        let count = usage.sub(s);
        if (count > 0)
            usage.upd(s, count - 1);
        return count - 1 == 0;
    endmethod

    method Action setFrame(SETS_LOG s, UInt#(32) count);
        usage.upd(s, count);
    endmethod

    method UInt#(32) getCount(SETS_LOG s);
        return usage.sub(s);
    endmethod

endmodule

endpackage
