package BankedMemory;

import Vector::*;
import RegFile::*;
import Types::*;
import Parameters::*;

// === Configuration ===

typedef Bit#(TMul#(TILE_SIZE, SizeOf#(Scalar))) TileRow;

// === Interface ===
interface BankedMemory_IFC;
    method Action write(SETS_LOG set, FRAMES_PER_SET_LOG frame, TaggedTile tile);
    method TaggedTile read(SETS_LOG set, FRAMES_PER_SET_LOG frame);
endinterface

// === Implementation ===
module mkBankedMemory(BankedMemory_IFC);

    // tile_banks[frame][row] gives access to the row regfile of a tile in a frame
    Vector#(FRAMES_PER_SET, Vector#(TILE_SIZE, RegFile#(SETS_LOG, TileRow))) tile_banks <- replicateM(
        replicateM(mkRegFileFull)
    );
    Vector#(FRAMES_PER_SET, RegFile#(SETS_LOG, StopToken)) stop_tokens <- replicateM(mkRegFileFull);

    method Action write(SETS_LOG set, FRAMES_PER_SET_LOG frame, TaggedTile tile);
        Vector#(TILE_SIZE, TileRow) rows = unpack(pack(tile.t));
        for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1)
            tile_banks[frame][i].upd(set, rows[i]);
        stop_tokens[frame].upd(set, tile.st);
    endmethod

    method TaggedTile read(SETS_LOG set, FRAMES_PER_SET_LOG frame);
        function TileRow get_row(RegFile#(SETS_LOG, TileRow) rf);
            return rf.sub(set);
        endfunction


        TaggedTile result;
        Vector#(TILE_SIZE, TileRow) rows = map(get_row, tile_banks[frame]);
        result.t = unpack(pack(rows));
        result.st = stop_tokens[frame].sub(set);
        return result;
    endmethod

endmodule

endpackage
