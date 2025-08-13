package Matmul;

import Types::*;
import Vector::*;
import FIFO::*;
import FIFOF::*;
import Parameters::*;
import PCUInstruction::*;

typedef 16 SYST_ARRAY_SIZE;
typedef 256 SYST_ARRAY_SIZE_SQUARED;

interface Matmul_IFC;
    method Action put_a(TaggedTile a);
    method Action put_b(TaggedTile b);
    method Action put_psum(TaggedTile psum);
    method ActionValue#(TaggedTile) get_a();
    method ActionValue#(TaggedTile) get_b();
    method ActionValue#(TaggedTile) get_psum();
    method ActionValue#(Int#(32)) get_bubbles();
endinterface

// Spatial Matrix Multiplication T (A * B^T) module
(* synthesize *)
module mkSpatialMatmulT#(
    Int#(16) row_position, 
    Int#(16) col_position,
    Int#(16) num_rows, 
    Bool forward_a,
    Bool psum_required,
    Bool bottom_right
)(Matmul_IFC);
    FIFOF#(TaggedTile) a_in <- mkFIFOF;
    FIFOF#(TaggedTile) b_in <- mkFIFOF;
    FIFOF#(TaggedTile) psum_in <- mkFIFOF;
    FIFOF#(TaggedTile) a_out <- mkFIFOF;
    FIFOF#(TaggedTile) b_out <- mkFIFOF;
    FIFOF#(TaggedTile) psum_out <- mkFIFOF;
    
    Reg#(Int#(32)) bubbles <- mkReg(0);

    Reg#(Int#(16)) weights_forwarded <- mkReg(0);
    Reg#(Int#(16)) inputs_processed <- mkReg(0);

    Reg#(Maybe#(TaggedTile)) a_processing <- mkReg(Invalid);
    FIFOF#(TaggedTile) b_processing <- mkFIFOF;
    Reg#(Maybe#(TaggedTile)) psum_processing <- mkReg(Invalid);
        
    rule pass_weight if (weights_forwarded < row_position);
        // Weights are loaded from the bottom up - Tile at row_position i forwards i weights and
        // then sets its own one    
        let b_tile = b_in.first;
        b_in.deq;
        b_out.enq(b_tile);

        weights_forwarded <= weights_forwarded + 1;
    endrule

    rule load_weight if (weights_forwarded == row_position);
        let b_tile = b_in.first;
        b_in.deq;
        b_processing.enq(b_tile);
        weights_forwarded <= 0;
    endrule

    (* preempts = "process_main_loop, pipeline_bubbles" *)
    // Main processing rule - processes matrix multiplication
    rule process_main_loop;
        // Process input data
        let a_tile = a_in.first;
        a_in.deq;

        let b = b_processing.first.t;
        let a = a_tile.t;
        let psum = matmul_t_tile(a, b);

        if (psum_required) begin
            let psum_tile = psum_in.first;
            psum_in.deq;
            psum = add_tile(psum, psum_tile.t);
        end

        if (forward_a) begin
            a_out.enq(a_tile); 
        end

        psum_out.enq(TaggedTile { t: psum, st: a_tile.st });

        if (inputs_processed == num_rows - 1) begin
            b_processing.deq;
            inputs_processed <= 0;
        end
        else begin
            inputs_processed <= inputs_processed + 1;
        end

        if (bottom_right) begin 
            // $display("Last sent something out");
        end
    endrule

    rule pipeline_bubbles;
        bubbles <= bubbles + 1;
        /*
        $display("Bubble because of row %d, col %d, a_in not empty %d, b_in not empty %d, psum_in not empty %d, a_out not full %d, b_out not full %d, psum_out not full %d", 
        row_position, col_position, 
        a_in.notEmpty,
        b_in.notEmpty,
        psum_in.notEmpty,
        a_out.notFull,
        b_out.notFull,
        psum_out.notFull);
        */
    endrule
    
    method Action put_a(TaggedTile a);
        // $display("put_a %d, %d: %s", row_position, col_position, fshow(a.t));
        a_in.enq(a);
    endmethod
    
    method Action put_b(TaggedTile b);
        // $display("put_b %d, %d: %s", row_position, col_position, fshow(b.t));
        b_in.enq(b);
    endmethod

    method Action put_psum(TaggedTile psum);
        // $display("put_psum %d, %d: %s", row_position, col_position, fshow(psum.t));
        psum_in.enq(psum);
    endmethod
    
    method ActionValue#(TaggedTile) get_a();
        // $display("get_a %d, %d", row_position, col_position);
        let a = a_out.first;
        a_out.deq;
        return a;
    endmethod

    method ActionValue#(TaggedTile) get_b();
        // $display("get_b %d, %d", row_position, col_position);
        let b = b_out.first;
        b_out.deq;
        return b;
    endmethod

    method ActionValue#(TaggedTile) get_psum();
        // $display("get_psum %d, %d", row_position, col_position);
        let psum = psum_out.first;
        psum_out.deq;
        return psum;
    endmethod

    method ActionValue#(Int#(32)) get_bubbles();
        return bubbles;
    endmethod
endmodule

function Module#(Matmul_IFC) mkMatmuls(Integer k);
    Module#(Matmul_IFC) el;

    let i = k / fromInteger(valueOf(SYST_ARRAY_SIZE));
    let j = k % fromInteger(valueOf(SYST_ARRAY_SIZE));

    let last = (k == valueOf(SYST_ARRAY_SIZE_SQUARED) - 1);
    let forward_a = (k < valueOf(SYST_ARRAY_SIZE) * (valueOf(SYST_ARRAY_SIZE) - 1));
    let psum_required = (j != 0);

    el = mkSpatialMatmulT(fromInteger(i), fromInteger(j), fromInteger(valueOf(SYST_ARRAY_SIZE)), forward_a, psum_required, last);
    return el;
endfunction

module mkMatmul(Empty);
    Vector#(SYST_ARRAY_SIZE_SQUARED, Matmul_IFC) matmuls <- genWithM(mkMatmuls);
    
    Int#(32) systolic_array_size = fromInteger(valueOf(SYST_ARRAY_SIZE));

    Reg#(Int#(32)) cycle <- mkReg(0);
    
    Reg#(Bit#(32)) num_lines <- mkReg(fromInteger(valueOf(SYST_ARRAY_SIZE)));
    Reg#(Bit#(32)) loaded <- mkReg(0);
    Reg#(Bit#(32)) drained <- mkReg(0);

    Reg#(Bit#(32)) loaded_a <- mkReg(0);
    Reg#(Bit#(32)) loaded_b <- mkReg(0);
    
    rule cycle_count;
        cycle <= cycle + 1;
    endrule

    for (Int#(32) i = 0; i < systolic_array_size - 1; i = i + 1) begin
        for (Int#(32) j = 0; j < systolic_array_size; j = j + 1) begin
            rule pass_a;
                let a <- matmuls[systolic_array_size * i + j].get_a;
                matmuls[systolic_array_size * (i + 1) + j].put_a(a);
            endrule
        end
    end 

    for (Int#(32) i = 0; i < systolic_array_size - 1; i = i + 1) begin
        for (Int#(32) j = 0; j < systolic_array_size; j = j + 1) begin
            rule pass_b;
                let b <- matmuls[systolic_array_size * (i + 1) + j].get_b;
                matmuls[systolic_array_size * i + j].put_b(b);
            endrule
        end
    end

    for (Int#(32) i = 0; i < systolic_array_size; i = i + 1) begin
        for (Int#(32) j = 0; j < systolic_array_size - 1; j = j + 1) begin
            rule put_psum;
                let psum <- matmuls[systolic_array_size * i + j].get_psum;
                matmuls[systolic_array_size * i + j + 1].put_psum(psum);
            endrule
        end
    end

    for (Int#(32) i = 0; i < systolic_array_size; i = i + 1) begin
        // (* preempts = "put_first_a, put_a_bubble" *)
        rule put_first_a if (loaded_a < num_lines);
            matmuls[i].put_a(TaggedTile { t: replicate(replicate(1)), st: 0 });
        endrule

        // rule put_a_bubble;
        //     $display("put_a_bubble");
        // endrule
    end

    for (Int#(32) i = 0; i < systolic_array_size; i = i + 1) begin
        // (* preempts = "put_first_b" *)
        rule put_first_b if (loaded_b < num_lines);
            
            matmuls[(systolic_array_size - 1) * systolic_array_size + i].put_b(TaggedTile { t: replicate(replicate(1)), st: 0 });
        endrule
        
        // rule put_b_bubble;
            // $display("put_b_bubble");
        // endrule
    end


    for (Int#(32) i = 0; i < systolic_array_size; i = i + 1) begin
         rule drain;
            let r1 <- matmuls[systolic_array_size * i + (systolic_array_size - 1)].get_psum;
            $display("result: ", fshow(r1.t));
            if (i == 0) begin
                drained <= drained + 1;
            end
        endrule
        
    end

    rule done if (drained == num_lines * num_lines);
        $display("Success!");
        $display("Cycles: %d", cycle);
        for (Int#(32) i = 0; i < systolic_array_size * systolic_array_size; i = i + 1) begin
            let bubbles <- matmuls[i].get_bubbles;
            $display("bubbles: %d", bubbles);
        end
        $finish(0);
    endrule

endmodule

endpackage