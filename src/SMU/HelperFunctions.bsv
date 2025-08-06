package HelperFunctions;

import Types::*;
import Parameters::*;
import Vector::*;

// ============================================================================
// Helper Functions
// ============================================================================

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
        2: return West;
        3: return East;
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

// Convert direction index to string name
function String directionIndexToName(UInt#(2) index);
    case (index) matches
        0: return "north";
        1: return "south";
        2: return "west";
        3: return "east";
        default: return "unknown";
    endcase
endfunction

// Get the direction to take one step toward target coordinates
function Direction getNeighborDirection(Coords current, Coords target);
    // Calculate differences
    Int#(33) dx = unpack(extend(pack(target.x))) - unpack(extend(pack(current.x)));
    Int#(33) dy = unpack(extend(pack(target.y))) - unpack(extend(pack(current.y)));
    
    // Determine which direction to go based on the larger difference
    // If x difference is larger (or equal), move horizontally
    if (abs(dx) >= abs(dy)) begin
        if (dx > 0) begin
            return East;
        end else if (dx < 0) begin
            return West;
        end else begin
            // dx == 0, move vertically
            if (dy > 0) begin
                return South;
            end else if (dy < 0) begin
                return North;
            end else begin
                // Were already at the target
                return North; // Default, shouldnt happen
            end
        end
    end else begin
        // y difference is larger, move vertically
        if (dy > 0) begin
            return South;
        end else if (dy < 0) begin
            return North;
        end else begin
            // dy == 0, move horizontally
            if (dx > 0) begin
                return East;
            end else if (dx < 0) begin
                return West;
            end else begin
                // Were already at the target
                return North; // Default, shouldnt happen
            end
        end
    end
endfunction

// Helper function to get absolute value
function Int#(33) abs(Int#(33) x);
    return (x < 0) ? -x : x;
endfunction

// Create a function to convert set and frame to index
function Bit#(TLog#(MAX_ENTRIES)) storageToIndex(UInt#(TLog#(SETS)) set, FRAME_INDEX frame);
    return zeroExtend(unpack(pack(set))) * fromInteger(valueOf(FRAMES_PER_SET)) + zeroExtend(unpack(pack(frame)));
endfunction

// Or create an overloaded version that takes StorageAddr
function Bit#(TLog#(MAX_ENTRIES)) storageAddrToIndex(StorageAddr addr);
    return storageToIndex(addr.set, addr.frame);
endfunction

function Maybe#(Bit#(2)) roundRobinFind(Bit#(32) start, Vector#(4, Bool) ready);
    Maybe#(Bit#(2)) return_val = tagged Invalid;
    Bool found = False;
    for (Integer i = 0; i < 4; i = i + 1) begin
        Bit#(2) idx = truncate((start + fromInteger(i)) % 4);
        if (!found && ready[idx]) begin
            return_val = tagged Valid idx;
            found = True;
        end
    end
    return return_val;
endfunction

endpackage