package HelperFunctions;

import Types::*;
import Parameters::*;

// ============================================================================
// Helper Functions
// ============================================================================

// pack and unpack set and frame into a single address
function StorageAddr packLocation(SET_INDEX set, FRAME_INDEX frame);
    return unpack({pack(set), pack(frame)});
endfunction

function Tuple2#(SET_INDEX, FRAME_INDEX) unpackLocation(StorageAddr addr);
    let frame_bits = valueOf(TLog#(FRAMES_PER_SET));
    SET_INDEX set = truncate(pack(addr) >> frame_bits);
    FRAME_INDEX frame = truncate(pack(addr));
    return tuple2(set, frame);
endfunction

// Process stop token
function Tuple2#(StopToken, Bool) processStopToken(StopToken st, Int#(32) rank); // returns new stop token and whether to emit the token
    if (st >= rank) begin
        return tuple2(st - rank, True);
    end else begin
        return tuple2(st, False);
    end
endfunction

endpackage