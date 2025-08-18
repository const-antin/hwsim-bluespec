package BankedMemory;

import BRAM::*;
import BRAMCore::*;
import Types::*;
import Parameters::*;

// Flat address: [set | frame]
typedef Bit#(TAdd#(TLog#(SETS), TLog#(FRAMES_PER_SET))) BankAddr;

function BankAddr flatAddr(SET_INDEX set, FRAME_INDEX frame);
  BankAddr s = zeroExtend(pack(set));
  BankAddr f = zeroExtend(pack(frame));
  return (s << valueOf(TLog#(FRAMES_PER_SET))) | f;
endfunction

// Store whole tile + stop token in one word
typedef Tuple2#(StopToken, Tile) EntryT;
typedef Bit#(SizeOf#(EntryT))   EntryBits;

interface BankedMemory_IFC;
  method Action write(SET_INDEX set, FRAME_INDEX frame, TaggedTile tile);
  method Action readReq(SET_INDEX set, FRAME_INDEX frame);
  method ActionValue#(TaggedTile) readRsp;
endinterface

module mkBankedMemory(BankedMemory_IFC);
  BRAM_Configure cfg = defaultValue;
  cfg.memorySize = valueOf(MAX_ENTRIES);
  cfg.latency    = 1;  // 1-cycle sync read
  // (Optionally set write-first if you care about read-during-write behavior)

  BRAM2Port#(BankAddr, EntryBits) ram <- mkBRAM2Server(cfg);

  method Action write(SET_INDEX set, FRAME_INDEX frame, TaggedTile tile);
    ram.portA.request.put(BRAMRequest{
      write: True, responseOnWrite: False,
      address: flatAddr(set, frame),
      datain: pack(tuple2(tile.st, tile.t))
    });
  endmethod

  method Action readReq(SET_INDEX set, FRAME_INDEX frame);
    ram.portB.request.put(BRAMRequest{
      write: False, responseOnWrite: False,
      address: flatAddr(set, frame),
      datain: ?
    });
  endmethod

  method ActionValue#(TaggedTile) readRsp;
    EntryBits e <- ram.portB.response.get;
    EntryT tup = unpack(e); // EntryT
    return TaggedTile { t: tpl_2(tup), st: tpl_1(tup) };
  endmethod
endmodule

endpackage

// package BankedMemory;

// import Vector::*;
// import RegFile::*;
// import ConfigReg::*;
// import Types::*;
// import Parameters::*;
// import BRAMCore::*;

// // === Configuration ===

// typedef Bit#(TMul#(TILE_SIZE, SizeOf#(Scalar))) TileRow;
// typedef UInt#(TAdd#(TLog#(SETS), TLog#(FRAMES_PER_SET))) BankAddr;

// // === Interface ===
// interface BankedMemory_IFC;
//     method Action write(SET_INDEX set, FRAME_INDEX frame, TaggedTile tile);
//     method TaggedTile read(SET_INDEX set, FRAME_INDEX frame);
// endinterface

// // === Implementation ===
// module mkBankedMemory(BankedMemory_IFC);

//     // Each bank holds FRAMES_PER_SET * SETS TileRows
//     Vector#(TILE_SIZE, RegFile#(BankAddr, TileRow)) banks <- replicateM(mkRegFileWCF(0, fromInteger(valueOf(MAX_ENTRIES) - 1)));

//     // Separate storage for StopTokens, shared across all banks
//     RegFile#(BankAddr, StopToken) stop_token_mem <- mkRegFileWCF(0, fromInteger(valueOf(MAX_ENTRIES) - 1));

//     // Compute flat address
//     function BankAddr flatAddr(SET_INDEX set, FRAME_INDEX frame);
//         return unpack(zeroExtend(pack(set)) << valueOf(TLog#(FRAMES_PER_SET)) | zeroExtend(pack(frame)));
//     endfunction

//     method Action write(SET_INDEX set, FRAME_INDEX frame, TaggedTile tile);
//         BankAddr addr = flatAddr(set, frame);
//         Vector#(TILE_SIZE, TileRow) rows = unpack(pack(tile.t));

//         for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1)
//             banks[i].upd(addr, rows[i]);

//         stop_token_mem.upd(addr, tile.st);
//     endmethod

//     method TaggedTile read(SET_INDEX set, FRAME_INDEX frame);
//         BankAddr addr = flatAddr(set, frame);
//         Vector#(TILE_SIZE, TileRow) rows;

//         for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1)
//             rows[i] = banks[i].sub(addr);

//         TaggedTile result;
//         result.t = unpack(pack(rows));
//         result.st = stop_token_mem.sub(addr);
//         return result;
//     endmethod

// endmodule

// endpackage
