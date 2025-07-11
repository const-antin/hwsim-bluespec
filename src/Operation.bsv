import FIFOF::*;
import FIFO::*;
import Vector::*;
import Assert::*;
import Types::*;

interface Operation_IFC;
    method Action put(Int#(32) input_port, ChannelMessage msg);
    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
endinterface

module mkAccum#(function Tile func (Tile tile, Tile tile2), Int#(32) rank) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    Reg#(Maybe#(Tile)) acc <- mkReg(tagged Invalid);

    rule do_accum if (input_fifo.first matches tagged Tag_Data .current);
        input_fifo.deq;

        let data = tpl_1(current);
        let st = tpl_2(current);

        Tile out;
        if (acc matches tagged Valid .tile) begin
            let tile2 = data.Tag_Tile;
            out = func(tile, tile2);
        end else begin
            out = data.Tag_Tile;
        end

        if (st >= rank) begin 
            let out_rank = st - rank;
            acc <= tagged Invalid;
            output_fifo.enq(tagged Tag_Data tuple2(tagged Tag_Tile out, out_rank));
        end else begin
            acc <= tagged Valid out;
        end

    endrule

    method Action put(Int#(32) input_port, ChannelMessage msg);
        input_fifo.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        output_fifo.deq;
        return output_fifo.first;
    endmethod
endmodule

module mkRepeatStatic#(Int#(32) num_repeats) (Operation_IFC);
    FIFOF#(ChannelMessage) input_fifo <- mkFIFOF;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    Reg#(Int#(32)) count <- mkReg(0);

    rule do_repeat if (count < num_repeats);
        let cur = input_fifo.first;

        if (cur matches tagged Tag_Data .current &&& count == num_repeats - 1) begin
            cur = tagged Tag_Data tuple2(tpl_1(current), tpl_2(current) + 1);
        end

        output_fifo.enq(cur);

        if (cur matches tagged Tag_Deallocate_Storage .ptr) begin
            input_fifo.deq;
        end
        else if (cur matches tagged Tag_Data .current) begin // This if is necessary so deallocates are not repeated
            count <= count + 1;
        end
    endrule

    rule dequeue if (count == num_repeats);
        input_fifo.deq;
        count <= 0;
    endrule

    method Action put(Int#(32) input_port, ChannelMessage msg);
        input_fifo.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        output_fifo.deq;
        return output_fifo.first;
    endmethod
endmodule

module mkBroadcast2 (Operation_IFC);
    let output_fifo1 <- mkFIFO;
    let output_fifo2 <- mkFIFO;

    method Action put(Int#(32) input_port, ChannelMessage msg);
        output_fifo1.enq(msg);
        output_fifo2.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        if (output_port == 0) begin
            output_fifo1.deq;
            return output_fifo1.first;
        end else begin
            output_fifo2.deq;
            return output_fifo2.first;
        end
    endmethod
endmodule

module mkUnaryMap#(function Tile func (Tile tile)) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    rule do_map;
        let cur = input_fifo.first;
        input_fifo.deq;

        if (cur matches tagged Tag_Data .current) begin 
            let out = func(tpl_1(current).Tag_Tile);
            output_fifo.enq(tagged Tag_Data tuple2(tagged Tag_Tile out, tpl_2(current)));
        end
    endrule

    method Action put(Int#(32) input_port, ChannelMessage msg);
        input_fifo.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        output_fifo.deq;
        return output_fifo.first;
    endmethod
endmodule

module mkBinaryMap#(function Tile func (Tile tile, Tile tile2)) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo1 <- mkFIFO;
    FIFO#(ChannelMessage) input_fifo2 <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    rule do_map;
        let cur_1 = input_fifo1.first;
        let cur_2 = input_fifo2.first;

        input_fifo1.deq;
        input_fifo2.deq;

        if (cur_1 matches tagged Tag_Data .current_1 &&& cur_2 matches tagged Tag_Data .current_2) begin
            let out = func(tpl_1(current_1).Tag_Tile, tpl_1(current_2).Tag_Tile);
            dynamicAssert(tpl_2(current_2) == tpl_2(current_1), "Stop tokens must be the same");
            output_fifo.enq(tagged Tag_Data tuple2(tagged Tag_Tile out, tpl_2(current_1)));
        end
    endrule

    method Action put(Int#(32) input_port, ChannelMessage msg);
        if (input_port == 0) begin
            input_fifo1.enq(msg);
        end else begin
            input_fifo2.enq(msg);
        end
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        output_fifo.deq;
        return output_fifo.first;
    endmethod
endmodule

module mkPromote(Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    rule do_promote;
        let cur = input_fifo.first;
        input_fifo.deq;

        if (cur matches tagged Tag_Data .current) begin
            let data = tpl_1(current);
            let st = tpl_2(current);
            output_fifo.enq(tagged Tag_Data tuple2(data, st + 1));
        end else begin 
            output_fifo.enq(cur);
        end
    endrule

    method Action put(Int#(32) input_port, ChannelMessage msg);
        input_fifo.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        output_fifo.deq;
        return output_fifo.first;
    endmethod
endmodule

module mkBufferize#(Int#(32) num_buffer_elements) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_token <- mkFIFO;
    FIFO#(ChannelMessage) input_token <- mkFIFO;
    FIFO#(ChannelMessage) output_data <- mkFIFO;

    // Reg#(Vector#(num_buffer_elements, ChannelMessage)) buffer <- mkReg(replicate(tagged Tag_EndToken));

    rule do_bufferize;
    endrule
endmodule

typedef enum {
    AccumBigTile_Fill,
    AccumBigTile_Accum,
    AccumBigTile_Drain
} AccumBigTileState deriving (Bits, Eq, FShow);

module mkAccumBigTile#(Int#(32) rank, function Tile func (Tile tile, Tile tile2)) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) partial_input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) partial_output_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    Reg#(AccumBigTileState) state <- mkReg(AccumBigTile_Fill);

    rule fill if (state == AccumBigTile_Fill);
        let cur = input_fifo.first;
        input_fifo.deq;
        
        let st = tpl_2(cur.Tag_Data);
        partial_output_fifo.enq(cur);

        if (st > rank) begin
            state <= AccumBigTile_Drain;
        end else if (st == rank) begin 
            state <= AccumBigTile_Accum;
        end
    endrule

    rule accumulate if (state == AccumBigTile_Accum);
        let add = input_fifo.first;
        let acc = partial_input_fifo.first;
        input_fifo.deq;
        partial_input_fifo.deq;

        let st = tpl_2(add.Tag_Data);
        let out = func(tpl_1(add.Tag_Data).Tag_Tile, tpl_1(acc.Tag_Data).Tag_Tile);

        if (st > rank) begin 
            state <= AccumBigTile_Drain;
        end 

        partial_output_fifo.enq(tagged Tag_Data tuple2(tagged Tag_Tile out, st));
    endrule

    rule drain if (state == AccumBigTile_Drain);
        let cur_in = partial_input_fifo.first;
        partial_input_fifo.deq;

        let data = cur_in.Tag_Data;
        let st = tpl_2(data);

        Int#(32) out_st;
        if (st >= rank) begin
            out_st = st - rank + 2;
        end else begin 
            out_st = st;
        end

        if (st >= rank) begin
            state <= AccumBigTile_Fill;
        end

        output_fifo.enq(tagged Tag_Data tuple2(tpl_1(data), out_st));
    endrule
    
    method Action put(Int#(32) input_port, ChannelMessage msg);
        if (input_port == 0) begin
            input_fifo.enq(msg);
        end else begin
            partial_input_fifo.enq(msg);
        end
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        if (output_port == 0) begin
            output_fifo.deq;
            return output_fifo.first;
        end else begin
            partial_output_fifo.deq;
            return partial_output_fifo.first;
        end
    endmethod
endmodule

module mkTop(Empty);
    let m1 <- mkBinaryMap(matmul_t_tile);
    let m2 <- mkBinaryMap(matmul_t_tile);

    let a1 <- mkAccum(add_tile, 1);
    let a2 <- mkAccum(add_tile, 1);

    let m3 <- mkBinaryMap(mul_tile);
    let m4 <- mkUnaryMap(silu_tile);

    let p5 <- mkPromote;

    let m6 <- mkBinaryMap(matmul_t_tile);
    let a7 <- mkAccum(add_tile, 1);

    rule stimulus;
        let tile = replicate(replicate(5));
        let msg = tagged Tag_Data tuple2(tagged Tag_Tile tile, 5);
        m1.put(0, msg);
        m1.put(1, msg);
        m2.put(0, msg);
        m2.put(1, msg);
        m6.put(1, msg);
    endrule

    rule pass_m1;
        let msg <- m1.get(0);
        a1.put(0, msg);
    endrule

    rule pass_m2;
        let msg <- m2.get(0);
        a2.put(0, msg);
    endrule

    rule pass_a1;
        let msg <- a1.get(0);
        m3.put(0, msg);
    endrule

    rule pass_a2;
        let msg <- a2.get(0);
        m4.put(0, msg);
    endrule

    rule pass_m4;
        let msg <- m4.get(0);
        m3.put(1, msg);
    endrule

    rule pass_m3;
        let msg <- m3.get(0);
        p5.put(0, msg);
    endrule

    rule pass_p5;
        let msg <- p5.get(0);
        m6.put(0, msg);
    endrule

    rule pass_m6;
        let msg <- m6.get(0);
        a7.put(0, msg);
    endrule

    rule drain;
        let msg <- a7.get(0);
        $display("Message: %s", fshow(msg));
        $finish;
    endrule
endmodule