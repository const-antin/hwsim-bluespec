package FileReader;

import Types::*;
import FShow::*;
import FIFOF::*;
import RegFile::*;

interface FileReader_IFC#(type entry_type);
    method ActionValue#(entry_type) readNext();
    method Bool isDone();
endinterface

module mkFileReader#(Integer num_entries, String filename) (FileReader_IFC#(entry_type)) provisos (Bits#(entry_type, entry_size));
    Reg#(Int#(32)) state <- mkReg(0);
    Reg#(Bit#(32)) index <- mkReg(0);
    FIFOF#(entry_type) entry_fifo <- mkFIFOF;

    RegFile#(Bit#(32), Bit#(entry_size)) entry_regfile <- mkRegFileLoad(filename, 0, fromInteger(num_entries));

    rule read if (index < fromInteger(num_entries));
        // $display("read index: %d", index);
        let t = entry_regfile.sub(index);
        let enq = unpack(t);
        entry_fifo.enq(enq);
        index <= index + 1;
    endrule

    method Bool isDone();
        return index == fromInteger(num_entries) && !entry_fifo.notEmpty;
    endmethod

    method ActionValue#(entry_type) readNext();
        entry_fifo.deq;
        return entry_fifo.first;
    endmethod
endmodule

module mkFileReaderTest(Empty);
    FileReader_IFC#(TaggedTile) reader <- mkFileReader(2, "gen_bsv/address_reader_0.hex");

    rule read_tile;
        let tile <- reader.readNext;
        $display("Read tile:", fshow(tile));
        // $finish(0);
    endrule
endmodule

endpackage