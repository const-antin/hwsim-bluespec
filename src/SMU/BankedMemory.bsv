package BankedMemory;

import Vector::*;
import RegFile::*;
import ConfigReg::*;
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
    Vector#(FRAMES_PER_SET, Vector#(TILE_SIZE, Vector#(SETS, ConfigReg#(TileRow)))) tile_banks <- replicateM(replicateM(replicateM(mkConfigReg(unpack(0)))));
    Vector#(FRAMES_PER_SET, Vector#(SETS, ConfigReg#(StopToken))) stop_tokens <- replicateM(replicateM(mkConfigReg(unpack(0))));

    method Action write(SETS_LOG set, FRAMES_PER_SET_LOG frame, TaggedTile tile);
        Vector#(TILE_SIZE, TileRow) rows = unpack(pack(tile.t));
        UInt#(TLog#(SETS)) set_int = unpack(set);
        for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1)
            tile_banks[frame][i][set_int] <= rows[i];
        stop_tokens[frame][set_int] <= tile.st;
    endmethod

    method TaggedTile read(SETS_LOG set, FRAMES_PER_SET_LOG frame);
        UInt#(TLog#(SETS)) set_int = unpack(set);

        TaggedTile result;
        Vector#(TILE_SIZE, TileRow) rows;
        for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1)
            rows[i] = tile_banks[frame][i][set_int];

        result.t = unpack(pack(rows));
        result.st = stop_tokens[frame][set_int];
        return result;
    endmethod

endmodule

endpackage
