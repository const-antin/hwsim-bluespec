package BankedMemory;

import Vector::*;
import RegFile::*;
import Types::*;
import Parameters::*;
import SetAllocator::*;

// === Configuration ===
typedef Bit#(TLog#(SETS)) SetIdx;       // 128 sets 2^7
typedef Bit#(TLog#(FRAMES_PER_SET)) FrameIdx;     // 8 tiles per set 2^3

typedef Vector#(TILE_SIZE, Scalar) TileRow;
typedef Vector#(TILE_SIZE, TileRow) Tile;

// === Interface ===
interface BankedMemory_IFC;
    method Action write(SetIdx set, FrameIdx frame, TaggedTile tile);
    method TaggedTile read(SetIdx set, FrameIdx frame);
endinterface

// === Implementation ===
module mkBankedMemory(BankedMemory_IFC);

    // tile_banks[frame][row] gives access to the row regfile of a tile in a frame
    Vector#(FRAMES_PER_SET, Vector#(TILE_SIZE, RegFile#(SetIdx, TileRow))) tile_banks <- replicateM(
        replicateM(mkRegFileFull)
    );
    Vector#(FRAMES_PER_SET, RegFile#(SetIdx, StopToken)) stop_tokens <- replicateM(mkRegFileFull);

    method Action write(SetIdx set, FrameIdx frame, TaggedTile tile);
        for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1)
            tile_banks[frame][i].upd(set, tile.t[i]);
        stop_tokens[frame].upd(set, tile.st);
    endmethod

    method TaggedTile read(SetIdx set, FrameIdx frame);
        function TileRow get_row(RegFile#(SetIdx, TileRow) rf);
            return rf.sub(set);
        endfunction


        TaggedTile result;
        result.t = map(get_row, tile_banks[frame]);
        result.st = stop_tokens[frame].sub(set);
        return result;
    endmethod

endmodule

endpackage
