package FileReader;

import Types::*;
import Vector::*;
import FShow::*;
import FIFO::*;
import FIFOF::*;
import RegFile::*;
import RamulatorInterface::*;

typedef 64 RAMULATOR_DATA_WIDTH;

interface FileReader_IFC#(type entry_type);
    method ActionValue#(entry_type) readNext();
    method Bool isDone();
endinterface

module mkFileReader#(Integer num_entries, String filename) (FileReader_IFC#(entry_type)) provisos (Bits#(entry_type, entry_size));
    Ramulator_IFC ramulator <- mkRamulator;

    Reg#(Bit#(64)) read_ptr <- mkReg(0); // Iterates through all addresses in the file

    // collect 64-bit responses until we have something of entry_size
    Reg#(UInt#(TLog#(TDiv#(entry_size, RAMULATOR_DATA_WIDTH)))) response_rr <- mkReg(0); 
    Vector#(TLog#(TDiv#(entry_size, RAMULATOR_DATA_WIDTH)), FIFO#(Bit#(64))) response_fifo_vec <- replicateM(mkFIFO);

    // aggregate responses into entry_type
    FIFOF#(entry_type) output_fifo <- mkFIFOF;

    // Actual data
    RegFile#(Bit#(64), Bit#(entry_size)) entry_regfile <- mkRegFileLoad(filename, 0, fromInteger(num_entries));

    rule read_request if (read_ptr < fromInteger(num_entries) * fromInteger(valueOf(TDiv#(entry_size, 8))));
        ramulator.send_request(read_ptr, False);
        read_ptr <= read_ptr + 8;
    endrule

    rule read_response;
        let response <- ramulator.get_response;
        response_fifo_vec[response_rr].enq(response);
        if (response_rr == fromInteger(valueOf(TDiv#(entry_size, RAMULATOR_DATA_WIDTH)))) begin
            response_rr <= 0;
        end else begin
            response_rr <= response_rr + 1;
        end
    endrule

    rule collect;
        let entry_idx = response_fifo_vec[0].first / (fromInteger(valueOf(entry_size)) / 8);
        $display("Read pointer: %d", entry_idx);
        output_fifo.enq(unpack(entry_regfile.sub(pack(entry_idx))));
        for (Integer i = 0; i < valueOf(TLog#(TDiv#(entry_size, RAMULATOR_DATA_WIDTH))); i = i + 1) begin
            response_fifo_vec[i].deq;
        end
    endrule 

    method Bool isDone();
        return !output_fifo.notEmpty && read_ptr >= fromInteger(num_entries) * fromInteger(valueOf(TDiv#(entry_size, 8)));
    endmethod

    method ActionValue#(entry_type) readNext();
        output_fifo.deq;
        return output_fifo.first;
    endmethod
endmodule

module mkFileReaderTest(Empty);
    FileReader_IFC#(TaggedTile) reader <- mkFileReader(8, "gen_bsv/address_reader_0.hex");

    Reg#(Bit#(64)) cycle_count <- mkReg(0);

    rule tick;
        cycle_count <= cycle_count + 1;
    endrule

    rule read_tile if (!reader.isDone);
        let tile <- reader.readNext;
        $display("Read tile at cycle %d:", cycle_count, fshow(tile));
        // $finish(0);
    endrule

    rule finish if (reader.isDone);
        $finish(0);
    endrule
endmodule

endpackage