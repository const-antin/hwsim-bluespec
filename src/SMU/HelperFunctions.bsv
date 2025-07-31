package HelperFunctions;

import Types::*;
import Parameters::*;

// ============================================================================
// Helper Functions
// ============================================================================

// pack and unpack set and frame into a single address
function StorageAddr packLocation(SET_INDEX set, FRAME_INDEX frame, CoordType x, CoordType y);
    return unpack({pack(set), pack(frame), pack(x), pack(y)});
endfunction

function Tuple4#(SET_INDEX, FRAME_INDEX, CoordType, CoordType) unpackLocation(StorageAddr addr);
    let frame_bits = valueOf(TLog#(FRAMES_PER_SET));
    let coord_bits = valueOf(TLog#(NUM_PMUS));
    
    SET_INDEX set = truncate(pack(addr) >> (frame_bits + 2 * coord_bits));
    FRAME_INDEX frame = truncate(pack(addr) >> (2 * coord_bits));
    CoordType x = unpack(truncate(pack(addr) >> coord_bits));
    CoordType y = unpack(truncate(pack(addr)));
    
    return tuple4(set, frame, x, y);
endfunction

// Process stop token
function Tuple2#(StopToken, Bool) processStopToken(StopToken st, Int#(32) rank); // returns new stop token and whether to emit the token
    if (st >= rank) begin
        return tuple2(st - rank, True);
    end else begin
        return tuple2(st, False);
    end
endfunction

// ============================================================================
// Direction Helper Functions
// ============================================================================

// Convert Direction to vector index
function UInt#(2) directionToIndex(Direction dir);
    case (dir) matches
        North: return 0;
        South: return 1;
        West:  return 2;
        East:  return 3;
    endcase
endfunction

// Convert vector index to Direction
function Direction indexToDirection(UInt#(2) index);
    case (index) matches
        0: return North;
        1: return South;
        2: return East;
        3: return West;
        default: return North; // Should never happen with 2-bit index
    endcase
endfunction

// Get the opposite direction
function Direction oppositeDirection(Direction dir);
    case (dir) matches
        North: return South;
        South: return North;
        East:  return West;
        West:  return East;
    endcase
endfunction

// Check if a direction is valid for a given position in a mesh
function Bool isValidDirection(Direction dir, UInt#(32) row, UInt#(32) col, UInt#(32) max_rows, UInt#(32) max_cols);
    case (dir) matches
        North: return (row > 0);
        South: return (row < max_rows - 1);
        East:  return (col < max_cols - 1);
        West:  return (col > 0);
    endcase
endfunction

// Get the neighbor position for a given direction
function Tuple2#(UInt#(32), UInt#(32)) getNeighborPosition(Direction dir, UInt#(32) row, UInt#(32) col);
    case (dir) matches
        North: return tuple2(row - 1, col);
        South: return tuple2(row + 1, col);
        East:  return tuple2(row, col + 1);
        West:  return tuple2(row, col - 1);
    endcase
endfunction

endpackage