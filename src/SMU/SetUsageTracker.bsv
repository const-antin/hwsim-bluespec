package SetUsageTracker;

import RegFile::*;
import Types::*;
import Parameters::*;

// Type aliases
typedef Bit#(TLog#(SETS)) SetIdx;
typedef Bit#(TLog#(TAdd#(FRAMES_PER_SET, 1))) FrameCount;

interface SetUsageTracker_IFC;
    method Action incFrame(SetIdx s);
    method Action decFrame(SetIdx s);
    method Bool isFull(SetIdx s);
    method Bool isEmpty(SetIdx s);
    method FrameCount getCount(SetIdx s);
endinterface

module mkSetUsageTracker(SetUsageTracker_IFC);
    RegFile#(SetIdx, FrameCount) usage <- mkRegFileFull;

    method Action incFrame(SetIdx s);
        let count = usage.sub(s);
        if (count < fromInteger(valueOf(FRAMES_PER_SET)))
            usage.upd(s, count + 1);
    endmethod

    method Action decFrame(SetIdx s);
        let count = usage.sub(s);
        if (count > 0)
            usage.upd(s, count - 1);
    endmethod

    method Bool isFull(SetIdx s);
        return usage.sub(s) == fromInteger(valueOf(FRAMES_PER_SET));
    endmethod

    method Bool isEmpty(SetIdx s);
        return usage.sub(s) == 0;
    endmethod

    method FrameCount getCount(SetIdx s);
        return usage.sub(s);
    endmethod

endmodule

endpackage
