import Operation::*;
import Bufferize::*;
import Types::*;
import Vector::*;
import FShow::*;
import FIFO::*;

function Int#(32) state_to_st(Int#(32) i);
    Int#(32) t;
    if (i == 0) begin t = 0; end
    else if (i == 1) begin t = 1; end
    else if (i == 2) begin t = 0; end 
    else if (i == 3) begin t = 2; end
    else if (i == 4) begin t = 0; end
    else if (i == 5) begin t = 1; end
    else if (i == 6) begin t = 0; end
    else if (i == 7) begin t = 2; end
    else if (i == 8) begin t = 0; end
    else if (i == 9) begin t = 1; end
    else if (i == 10) begin t = 0; end
    else if (i == 11) begin t = 2; end
    else if (i == 12) begin t = 0; end
    else if (i == 13) begin t = 1; end
    else if (i == 14) begin t = 0; end
    else begin t = 3; end
    return t;
endfunction

function Int#(32) state_to_output_st(Int#(32) i);
    Int#(32) t;
    if (i == 0) begin t = 0; end
    else if (i == 1) begin t = 1; end
    else if (i == 2) begin t = 0; end
    else begin t = 2; end
    return t;
endfunction

module mkAccumBigTileTest(Empty);
    let accum_rank = 3;
    let accum <- mkAccumBigTile(add_tile, accum_rank);
    let sized_fifo <- mkSizedFIFO(128);

    Reg#(Int#(32)) state <- mkReg(0);
    Reg#(Int#(32)) drained <- mkReg(0);

    for (Int#(32) i = 0; i < 16; i = i + 1) begin 
        rule send (state == i);
            let tile = Tag_Tile(1);
            accum.put(0, Tag_Data(tuple2(tile, state_to_st(i))));
            state <= state + 1;
        endrule
    end

    rule connect_accum_to_buf;
        let k <- accum.get(0);
        sized_fifo.enq(k);
    endrule

    rule connect_partial_to_accum;
        let k = sized_fifo.first();
        sized_fifo.deq();
        accum.put(1, k);
    endrule

    rule drain;
        ChannelMessage k <- accum.get(1);
        
        if (tpl_1(k.Tag_Data).Tag_Tile != 4 || tpl_2(k.Tag_Data) != state_to_output_st(drained)) begin
            $display("FAIL");
            $finish(-1);
        end
        $display("drained: %d (Tile ", drained, fshow(k), ")");
        drained <= drained + 1;
    endrule

    rule finish;
        if (drained == 4) begin
            $display("SUCCESS");
            $finish(0);
        end
    endrule
endmodule

module mkAccumBigTileWithBufferizeTest(Empty);
    let accum_rank = 3;
    let accum <- mkAccumBigTile(add_tile, accum_rank);
    Bufferize#(16, 4) bufferize <- mkSimpleBufferize(16, 2, 4);

    Reg#(Int#(32)) state <- mkReg(0);
    Reg#(Int#(32)) drained <- mkReg(0);

    for (Int#(32) i = 0; i < 16; i = i + 1) begin 
        rule send (state == i);
            let tile = Tag_Tile(1);
            accum.put(0, Tag_Data(tuple2(tile, state_to_st(i))));
            state <= state + 1;
        endrule
    end

    rule connect_accum_to_bufferize;
        let k <- accum.get(0);
        bufferize.put_data(k);
    endrule

    rule bufferize_loop;
        let k <- bufferize.get_token();
        bufferize.request_token(k);
    endrule

    rule connect_bufferize_to_accum;
        let k <- bufferize.get_data();
        accum.put(1, k);
    endrule

    rule drain;
        ChannelMessage k <- accum.get(1);
        
        if (tpl_1(k.Tag_Data).Tag_Tile != 4 || tpl_2(k.Tag_Data) != state_to_output_st(drained)) begin
            $display("FAIL");
            $finish(-1);
        end
        $display("drained: %d (Tile ", drained, fshow(k), ")");
        drained <= drained + 1;
    endrule

    rule finish;
        if (drained == 4) begin
            $display("SUCCESS");
            $finish(0);
        end
    endrule
endmodule