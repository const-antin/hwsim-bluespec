import Vector::*;
import FIFO::*;
import FIFOF::*;

import RamulatorFIFO::*;

typedef 2 NUM_PORTS;

interface RamulatorArbiter_IFC;
    method Action send_request(Bit#(8) port_id, Bit#(56) addr, Bool is_write);
    method ActionValue#(Bit#(56)) get_response(Bit#(8) port_id);
endinterface

module mkRamulatorArbiter (RamulatorArbiter_IFC);
    Vector#(NUM_PORTS, FIFOF#(Tuple2#(Bit#(56), Bool))) requests <- replicateM(mkFIFOF);
    Vector#(NUM_PORTS, FIFOF#(Bit#(56))) responses <- replicateM(mkFIFOF);
    FIFO#(Tuple2#(Bit#(64), Bool)) ramulator_requests <- mkFIFO;
    FIFO#(Bit#(64)) ramulator_responses <- mkFIFO;
    RamulatorFIFO_IFC ramulator <- mkRamulatorFIFO;

    Reg#(Bit#(8)) enqueue_idx <- mkReg(0);
    Wire#(Bit#(8)) next_enqueue_idx <- mkWire;

    for (Integer i = 0; i < valueOf(NUM_PORTS); i = i + 1) begin
        rule enqueue_requests if (next_enqueue_idx == fromInteger(i));
            if (responses[i].notFull) begin
                ramulator_requests.enq(
                    tuple2(
                        {fromInteger(i), tpl_1(requests[i].first)},
                        tpl_2(requests[i].first)
                    )
                );
                requests[i].deq;
            end
        endrule
    end

    rule get_next_enqueue_idx;
        Bool found = False;
        for (Bit#(8) i = 0; i < fromInteger(valueOf(NUM_PORTS)); i = i + 1) begin
            let idx = (enqueue_idx + i) % fromInteger(valueOf(NUM_PORTS));
            if (requests[idx].notEmpty && !found) begin
                next_enqueue_idx <= idx;
                found = True;
                enqueue_idx <= (idx + 1) % fromInteger(valueOf(NUM_PORTS));
            end
        end
    endrule

    rule feed_ramulator;
        ramulator.send_request(tpl_1(ramulator_requests.first), tpl_2(ramulator_requests.first));
        ramulator_requests.deq;
    endrule

    rule drain_ramulator;
        let response <- ramulator.get_response;
        ramulator_responses.enq(response);
    endrule

    rule dequeue_responses;
        let response = ramulator_responses.first;
        ramulator_responses.deq;
        let port_id = response[63:56];
        let addr = response[55:0];
        responses[port_id].enq(addr);
    endrule

    method Action send_request(Bit#(8) port_id, Bit#(56) addr, Bool is_write);
        requests[port_id].enq(tuple2(addr, is_write));
    endmethod 

    method ActionValue#(Bit#(56)) get_response(Bit#(8) port_id);
        responses[port_id].deq;
        return responses[port_id].first;
    endmethod
endmodule

module mkRamulatorArbiterTest(Empty);
    RamulatorArbiter_IFC arbiter <- mkRamulatorArbiter;

    let num_requests = 1000;

    Reg#(Bit#(32)) sent_requests_a <- mkReg(0);
    Reg#(Bit#(32)) sent_requests_b <- mkReg(0);

    Reg#(Bit#(32)) received_responses_a <- mkReg(0);
    Reg#(Bit#(32)) received_responses_b <- mkReg(0);

    Reg#(Bit#(32)) cycle <- mkReg(0);

    rule cc;
        cycle <= cycle + 1;
    endrule

    rule send_request_a if (sent_requests_a < num_requests);
        // $display("Sent a request (a)");
        arbiter.send_request(0, extend(sent_requests_a), False);
        sent_requests_a <= sent_requests_a + 1;
    endrule

    rule send_request_b if (sent_requests_b < num_requests);
        // $display("Sent a request (b)");
        arbiter.send_request(1, extend(num_requests + sent_requests_b), False);
        sent_requests_b <= sent_requests_b + 1;
    endrule

    rule get_response_a if (received_responses_a < num_requests);
        let addr <- arbiter.get_response(0);
        $display("Response: %d at cycle %d", addr, cycle);
        received_responses_a <= received_responses_a + 1;
        if (addr != extend(received_responses_a)) begin
            $display("Error: Response %d does not match expected response %d", addr, received_responses_a);
            // $finish(1);
        end
    endrule

    rule get_response_b if (received_responses_b < num_requests);
        let addr <- arbiter.get_response(1);
        $display("Response: %d at cycle %d", addr, cycle);
        received_responses_b <= received_responses_b + 1;
        if (addr != extend(num_requests + received_responses_b)) begin
            $display("Error: Response %d does not match expected response %d", addr, num_requests + received_responses_b);
            // $finish(1);
        end
    endrule

    rule exit if (received_responses_a == num_requests && received_responses_b == num_requests);
        $finish(0);
    endrule
endmodule