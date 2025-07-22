package FileReader;

`define FILE_READER_PADDED_TO_64 TMul#(TDiv#(entry_size_unpadded, 64), 64)

import Types::*;
import Vector::*;
import FShow::*;
import FIFO::*;
import FIFOF::*;
import RegFile::*;
import RamulatorArbiter::*;
import Assert::*;

typedef 64 RAMULATOR_DATA_WIDTH;

interface FileReader_IFC#(type entry_type);
    method ActionValue#(entry_type) readNext();
    method Bool isDone();
endinterface

module mkFileReader#(
    Integer num_entries, 
    String filename,
    Bit#(8) index,
    RamulatorArbiterIO arbiter
    ) (FileReader_IFC#(entry_type)) provisos (Bits#(entry_type, entry_size_unpadded));

    // For simulation purposes, we assume that each input hex file is padded to 64-bit lines.
    // If it isnt, the ramulator part virtually pads the input to 64-bit lines.
    // This does not have any effect on the read data, but on timing, and simplifies address generation for ramulator.
    staticAssert(valueOf(`FILE_READER_PADDED_TO_64) % 64 == 0, "entry_size must be a multiple of 64");

    Reg#(Bit#(64)) read_ptr <- mkReg(0); // Iterates through all addresses in the file
    Reg#(Bit#(64)) entry_idx <- mkReg(0); // Iterates through all entries in the file

    // collect 64-bit responses until we have something of entry_size
    Reg#(UInt#(32)) response_rr <- mkReg(0); 
    Vector#(TDiv#(`FILE_READER_PADDED_TO_64, RAMULATOR_DATA_WIDTH), FIFO#(Bit#(64))) response_fifo_vec <- replicateM(mkFIFO);

    // aggregate responses into entry_type
    FIFOF#(entry_type) output_fifo <- mkFIFOF;

    // Actual data
    RegFile#(Bit#(64), Bit#(entry_size_unpadded)) entry_regfile <- mkRegFileLoad(filename, 0, fromInteger(num_entries));

    Reg#(Bit#(64)) read_requests_issued <- mkReg(0);
    Reg#(Bit#(64)) read_responses_received <- mkReg(0);

    rule read_request if (read_ptr <= fromInteger(num_entries) * fromInteger(valueOf(TDiv#(`FILE_READER_PADDED_TO_64, 8))));
        arbiter.send_request(index, truncate(read_ptr), False);
        read_ptr <= read_ptr + 8;
        read_requests_issued <= read_requests_issued + 1;
        // $display("Read request issued: %d", read_requests_issued);
    endrule        

    rule read_response;
        let response <- arbiter.get_response(index);
        response_fifo_vec[response_rr].enq(extend(response));
        if (response_rr + 1 == fromInteger(valueOf(TDiv#(`FILE_READER_PADDED_TO_64, RAMULATOR_DATA_WIDTH)))) begin
            response_rr <= 0;
        end else begin
            response_rr <= response_rr + 1;
        end
        read_responses_received <= read_responses_received + 1;
        // $display("Read response received: %d, put into %d", read_responses_received, response_rr);
    endrule

    function Action dequeue(FIFO#(Bit#(64)) fifo);
        return fifo.deq;
    endfunction

    rule collect;
        // $display("Entry index (Reader %d): %d", index, entry_idx);
        output_fifo.enq(unpack(entry_regfile.sub(pack(entry_idx))));

        mapM_(dequeue, response_fifo_vec);
        entry_idx <= entry_idx + 1;
    endrule

    method Bool isDone();
        return !output_fifo.notEmpty && entry_idx >= fromInteger(num_entries);
    endmethod

    method ActionValue#(entry_type) readNext();
        output_fifo.deq;
        return output_fifo.first;
    endmethod
endmodule

module mkFileReaderTest(Empty);
    RamulatorArbiter_IFC#(1) arbiter <- mkRamulatorArbiter(1);
    FileReader_IFC#(TaggedTile) reader <- mkFileReader(128, "gen_bsv/address_reader_0.hex", 0, arbiter.ports);

    Reg#(Bit#(64)) cycle_count <- mkReg(0);

    rule tick;
        cycle_count <= cycle_count + 1;
    endrule

    rule read_tile;
        let tile <- reader.readNext;
        $display("Read tile at cycle %d:", cycle_count, fshow(tile));
        // $finish(0);
    endrule

    rule finish if (reader.isDone);
        // $finish(0);
    endrule
endmodule

endpackage