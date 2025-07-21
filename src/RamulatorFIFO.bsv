// This module takes the responses from ramulator and returns them in FIFO request/response order. 
// This is required since ramulator2 dropped the FIFO interface.. 

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import RegFile::*;
import Vector::*;
import RamulatorInterface::*;

interface RamulatorFIFO_IFC;
    method Action send_request(Bit#(64) addr, Bool is_write);
    method ActionValue#(Bit#(64)) get_response();
endinterface

typedef 8 NUM_IN_FLIGHT;
typedef Bit#(TLog#(NUM_IN_FLIGHT)) Tag;

module mkRamulatorFIFO(RamulatorFIFO_IFC);
    FIFO#(Tuple2#(Bit#(64), Bool)) in <- mkFIFO;
    FIFO#(Bit#(64)) out <- mkFIFO;
    Ramulator_IFC ramulator <- mkRamulator;

    Vector#(NUM_IN_FLIGHT, FIFOF#(Bit#(64))) requests <- replicateM(mkSizedFIFOF(1));
    FIFO#(Bit#(64)) in_flight <- mkSizedFIFO(valueOf(NUM_IN_FLIGHT));
    
    Wire#(Bit#(TLog#(NUM_IN_FLIGHT))) next_location <- mkWire;
    Wire#(Bit#(TLog#(NUM_IN_FLIGHT))) free_location <- mkWire;

    rule put_req;
        let addr = tpl_1(in.first);
        let is_write = tpl_2(in.first);
        ramulator.send_request(addr, is_write);
        in_flight.enq(addr);
        in.deq;
        // $display("Sent request to ramulator: 0x%x", addr);
    endrule

    rule find_free;
        Bool found = False;
        for (Integer i = 0; i < fromInteger(valueOf(NUM_IN_FLIGHT)); i = i + 1) begin
            if (requests[i].notFull && !found) begin
                free_location <= fromInteger(i);
                found = True;
            end
        end
    endrule 

    rule get_resp;
        let response <- ramulator.get_response();
        // $display("Ramulator response: 0x%x, enqueing to location %d", response, free_location);
        requests[free_location].enq(response);
        // $display("Enqueued the response for 0x%x", response);
    endrule

    rule find_next;
        Bool found = False;
        for (Integer i = 0; i < fromInteger(valueOf(NUM_IN_FLIGHT)); i = i + 1) begin
            if (requests[i].notEmpty && requests[i].first == in_flight.first && !found) begin
                next_location <= fromInteger(i);
                // $display("Found the response for 0x%x", in_flight.first, fshow(requests));
                found = True;
            end
        end
        if (!found) begin
            // $error("Did not find the response for 0x%x", in_flight.first, fshow(requests));
        end
    endrule

    rule drain_next;
        let response = requests[next_location].first;
        requests[next_location].deq;
        in_flight.deq;
        // $display("Drained the response for 0x%x", in_flight.first);
        out.enq(response);
    endrule

    method Action send_request(Bit#(64) addr, Bool is_write);
        // $display("Sending request to ramulator: 0x%x", addr);
        in.enq(tuple2(addr, is_write));
    endmethod
    
    method ActionValue#(Bit#(64)) get_response();
        out.deq;
        // $display("Dequeued the response for 0x%x", out.first);
        return out.first;
    endmethod

endmodule

module mkRamulatorFIFOTest(Empty);
    Reg#(Int#(32)) sent <- mkReg(0);
    Reg#(Int#(32)) received <- mkReg(0);
    
    Int#(32) num_elements = 10000;
    RamulatorFIFO_IFC fifo_ram <- mkRamulatorFIFO;
    
    rule send if (sent < num_elements);
        fifo_ram.send_request(zeroExtend(pack(sent)) << 8, False);
        sent <= sent + 1;
    endrule

    rule receive if (received < num_elements);
        let response <- fifo_ram.get_response();
        if (response == zeroExtend(pack(received) << 8)) begin
            received <= received + 1;
        end else begin
            $error("Received the wrong response for 0x%x", response);
        end
    endrule

    rule finish if (sent == num_elements && received == num_elements);
        $display("SUCCESS");
        $finish(0);
    endrule
endmodule
