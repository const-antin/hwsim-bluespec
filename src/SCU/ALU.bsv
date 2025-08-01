import Types::*;
import FIFO::*;

typedef enum {
    ADD_FP32,
    SUB_FP32,
    MUL_FP32,
    DIV_FP32,
    LT_FP32,
    MAX_FP32,
    MIN_FP32,
    EXP_FP32,
    POW_FP32,
    COS_FP32,
    SIN_FP32,
    LEQ_FP32,
    MODULO_FP32,
    NEGATE_FP32,
    ID,
    SQUARE_FP32,
    TANH_FP32,
    MATMUL_FP32,
    MATMUL_T_FP32,
    SCALE_ADD_FP32,
    SILU_FP32
} Opcode deriving (Bits, Eq);


interface ALU_IFC;
    method Action put(Integer port_idx, Tile tile);
    method Action set_opcode(Opcode opcode);
    method ActionValue#(Tile) get_result();
endinterface

// ALU in a PCU for computing on tiles.
module mkALU(ALU_IFC);
    FIFO#(Tile) a_fifo <- mkFIFO;
    FIFO#(Tile) b_fifo <- mkFIFO;
    FIFO#(Tile) c_fifo <- mkFIFO;
    FIFO#(Tile) result_fifo <- mkFIFO;
    Reg#(Opcode) opcode <- mkReg(ID);

    (* preempts = "(add, sub, mul, div), otherwise" *)
    rule add;
        let a = a_fifo.first;
        let b = b_fifo.first;
        let result = add_tile(a, b);
        result_fifo.enq(result);
        a_fifo.deq;
        b_fifo.deq;
    endrule

    rule sub;
        let a = a_fifo.first;
        let b = b_fifo.first;
        let result = sub_tile(a, b);
        result_fifo.enq(result);
        a_fifo.deq;
        b_fifo.deq;
    endrule

    rule mul;
        let a = a_fifo.first;
        let b = b_fifo.first;
        let result = mul_tile(a, b);
        result_fifo.enq(result);
        a_fifo.deq;
        b_fifo.deq;
    endrule

    rule div;
        let a = a_fifo.first;
        let b = b_fifo.first;
        let result = div_tile(a, b);
        result_fifo.enq(result);
        a_fifo.deq;
        b_fifo.deq;
    endrule

    rule otherwise;
        a_fifo.deq;
        $display("Opcode not implemented: %d", opcode);
        $finish(0);
    endrule

    method Action put(Integer port_idx, Tile tile);
        if (port_idx == 0) begin
            a_fifo.enq(tile);
        end else if (port_idx == 1) begin
            b_fifo.enq(tile);
        end else if (port_idx == 2) begin
            c_fifo.enq(tile);
        end else begin
            $display("Invalid port index: %d", port_idx);
            $finish(0);
        end
    endmethod

    method Action set_opcode(Opcode opcode_in);
        opcode <= opcode_in;
    endmethod

    method ActionValue#(Tile) get_result();
        result_fifo.deq;
        return result_fifo.first;
    endmethod
endmodule

module testALU(Empty);
    ALU_IFC alu <- mkALU;
    Reg#(Bool) done <- mkReg(False);

    rule test if (!done);
        alu.put(0, 1); // a
        alu.put(1, 2); // b
        alu.set_opcode(ADD_FP32);
        done <= True;
        $display("Put a and b");
    endrule

    rule drain;
        let result = alu.get_result();
        $display("Result: %d", result);
        $finish(0);
    endrule
endmodule