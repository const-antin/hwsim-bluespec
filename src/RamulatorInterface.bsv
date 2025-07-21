import FIFO::*;

// General ramulator functions
import "BDPI" function Action init_ramulator();
import "BDPI" function Action free_ramulator();
import "BDPI" function ActionValue#(Bool) ramulator_send(Bit#(64) addr, Bool is_write);
import "BDPI" function Action ramulator_tick();
import "BDPI" function ActionValue#(Bit#(64)) ramulator_get_cycle();
import "BDPI" function Bool ramulator_ret_available();
import "BDPI" function ActionValue#(Bit#(64)) ramulator_pop();
import "BDPI" function ActionValue#(Bool) ramulator_is_finished();

// Byte-Addressed Interface
interface Ramulator_IFC;
    method Action send_request(Bit#(64) addr, Bool is_write);
    method ActionValue#(Bit#(64)) get_response();
endinterface

module mkRamulator(Ramulator_IFC);
    Reg#(Bit#(64)) cycle_count <- mkReg(0);
    Reg#(Bool) initialized <- mkReg(False);
    Reg#(Bool) finished <- mkReg(False);
    FIFO#(Tuple2#(Bit#(64), Bool)) requests <- mkFIFO;
    FIFO#(Bit#(64)) responses <- mkFIFO;

    rule init_ramulator(!initialized);
        init_ramulator();
        initialized <= True;
    endrule

    rule send_requests(initialized);
        let success <- ramulator_send(tpl_1(requests.first), tpl_2(requests.first));
        if (success) begin
            // $display("Sending request to address: 0x%x at cycle %d", tpl_1(requests.first), cycle_count);
            // $display("Sent request to address: 0x%x at cycle %d", tpl_1(requests.first), cycle_count);
            requests.deq;
        end else begin 
            // $display("Failed to send request to ramulator, trying again next cycle");
        end
    endrule

    rule incr_cycle if (initialized);
        cycle_count <= cycle_count + 1;
        ramulator_tick();
    endrule

    rule drain if (initialized);
        if (ramulator_ret_available()) begin
            let addr <- ramulator_pop();
            // $display("Received return for address: 0x%x at cycle %d", addr, cycle_count);
            responses.enq(addr);
        end
    endrule

    method Action send_request(Bit#(64) addr, Bool is_write) if (initialized);
        requests.enq(tuple2(addr, is_write));
    endmethod

    method ActionValue#(Bit#(64)) get_response() if (initialized);
        responses.deq;
        return responses.first;
    endmethod
endmodule

module mkRamulatorTest(Empty);
    Ramulator_IFC ramulator <- mkRamulator;
    Reg#(Int#(32)) sent <- mkReg(0);
    Reg#(Int#(32)) received <- mkReg(0);

    rule send_requests if (sent < 10);
        ramulator.send_request(zeroExtend(pack(sent) << 8), False);
        sent <= sent + 1;
    endrule

    rule get_responses if (received < 10);
        let response <- ramulator.get_response();
        $display("Received response: 0x%x", response);
        received <= received + 1;
    endrule

    rule finish if (received == 10);
        $finish;
    endrule
endmodule