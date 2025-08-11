package Operation;

import FIFOF::*;
import FIFO::*;
import Vector::*;
import Assert::*;
import Types::*;
import FileReader::*;
import RamulatorArbiter::*;
import StmtFSM::*;

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

(* synthesize *)
module mkRepeatStatic#(Int#(32) num_repeats) (Operation_IFC);
    FIFOF#(ChannelMessage) input_fifo <- mkFIFOF;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    Reg#(Int#(32)) count <- mkReg(0);

    rule do_repeat if (count < num_repeats);
        let cur = input_fifo.first;

        if (cur matches tagged Tag_Data .current) begin
            Data to_send = tpl_1(current);
            if (count == num_repeats - 1) begin
                if (to_send matches tagged Tag_Ref .r) begin
                    to_send = tagged Tag_Ref tuple2(tpl_1(r), True);
                end
                cur = tagged Tag_Data tuple2(to_send, tpl_2(current) + 1);
            end else begin 
                if (to_send matches tagged Tag_Ref .r) begin
                    to_send = tagged Tag_Ref tuple2(tpl_1(r), False);
                end
                cur = tagged Tag_Data tuple2(to_send, 0);
            end
        end

        output_fifo.enq(cur);

        if (cur matches tagged Tag_Data .current) begin // This if is necessary so deallocates are not repeated
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

interface Broadcast_IFC#(numeric type degree);
    interface Operation_IFC op;
endinterface

module mkBroadcast#(Integer degree) (Broadcast_IFC#(degree));
    Vector#(degree, FIFO#(ChannelMessage)) output_fifos <- replicateM(mkFIFO);

    interface Operation_IFC op;
    method Action put(Int#(32) input_port, ChannelMessage msg);
        for (Integer i = 0; i < degree; i = i + 1) begin
            output_fifos[i].enq(msg);
        end
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        ChannelMessage ret;
        if (output_port < fromInteger(degree)) begin
            output_fifos[output_port].deq;
            ret = output_fifos[output_port].first;
        end else begin
            $display("Error: Invalid output port %d for broadcast with degree %d", output_port, degree);
            $finish(-1);
            ret = tagged Tag_EndToken; // This is just to satisfy the return type, it will never be used.
        end 
        return ret;
    endmethod
    endinterface
endmodule

(* synthesize *)
module mkFlatten#(Int#(32) rank) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;


    rule do_flatten;
        let cur = input_fifo.first;
        input_fifo.deq;
        
        if (cur matches tagged Tag_Data .current) begin
            let data = tpl_1(current);
            let st = tpl_2(current);
            
            StopToken out_st;
            if (st == rank) begin
                out_st = 0;
            end else if (st > rank) begin
                out_st = st - 1;
            end else begin
                out_st = st;
            end
            
            output_fifo.enq(tagged Tag_Data tuple2(data, out_st));
        end else if (cur matches tagged Tag_EndToken) begin
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

module mkUnaryMap#(Integer id, function Tile func (Tile tile)) (Operation_IFC);
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

module mkBinaryMap#(Int#(32) id, function Tile func (Tile tile, Tile tile2)) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo1 <- mkFIFO;
    FIFO#(ChannelMessage) input_fifo2 <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;
    Reg#(Int#(32)) count <- mkReg(0);

    rule do_map;
        let cur_1 = input_fifo1.first;
        let cur_2 = input_fifo2.first;

        input_fifo1.deq;
        input_fifo2.deq;

        if (cur_1 matches tagged Tag_Data .current_1 &&& cur_2 matches tagged Tag_Data .current_2) begin
            let out = func(tpl_1(current_1).Tag_Tile, tpl_1(current_2).Tag_Tile);
            $display("ST1: %d, ST2: %d, count: %d, id: %d", tpl_2(current_1), tpl_2(current_2), count, id);
            if (tpl_2(current_2) != tpl_2(current_1)) begin
                $error("id: %d, Stop tokens are not the same at cycle %d, left: %d, right: %d", id, count, tpl_2(current_1), tpl_2(current_2));
                $finish;
                // $finish;
            end
            // dynamicAssert(tpl_2(current_2) == tpl_2(current_1), "Stop tokens must be the same");
            output_fifo.enq(tagged Tag_Data tuple2(tagged Tag_Tile out, tpl_2(current_1)));
            count <= count + 1;
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

(* synthesize *)
module mkPromote#(Int#(32) rank) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    rule do_promote;
        let cur = input_fifo.first;
        input_fifo.deq;

        if (cur matches tagged Tag_Data .current) begin
            let data = tpl_1(current);
            let st = tpl_2(current);
            let st_out = (st >= rank) ? st + 1 : st;
            output_fifo.enq(tagged Tag_Data tuple2(data, st_out));
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

(* synthesize *)
module mkPartition#(Int#(32) rank, Int#(32) num_outputs) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;
    
    method Action put(Int#(32) input_port, ChannelMessage msg);
        input_fifo.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        output_fifo.deq;
        return output_fifo.first;
    endmethod
endmodule

typedef enum {
    AccumBigTile_Fill,
    AccumBigTile_Accum,
    AccumBigTile_Drain
} AccumBigTileState deriving (Bits, Eq, FShow);

module mkAccumBigTile#(function Tile func (Tile tile, Tile tile2), Int#(32) rank) (Operation_IFC);
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

        if (st >= rank) begin
            state <= AccumBigTile_Drain;
        end else if (st == 2) begin 
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

        if (st >= rank) begin 
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
            partial_output_fifo.deq;
            return partial_output_fifo.first;
        end else begin
            output_fifo.deq;
            return output_fifo.first;
        end
    endmethod
endmodule

module mkTileReader#(Integer num_entries, String filename, Bit#(8) port_id, RamulatorArbiterIO arbiter) (Operation_IFC);
    FileReader_IFC#(TaggedTile) reader <- mkFileReader(num_entries, filename, port_id, arbiter);

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        TaggedTile tile <- reader.readNext;
        return tagged Tag_Data tuple2(tagged Tag_Tile tile.t, tile.st);
    endmethod 

    method Action put(Int#(32) input_port, ChannelMessage msg);
        $error("TileReader does not support put");
    endmethod
endmodule

(* synthesize *)
module mkPrinter#(parameter String name) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    Reg#(Int#(64)) cc <- mkReg(0);

    rule print;
        let cur = input_fifo.first;
        input_fifo.deq;
        
        $display("[cycle %d] %s: %s", cc, name, fshow(cur));

        if (tpl_2(cur.Tag_Data) == 5) begin // Hardcoded for Gina's application.
            $display("Finished at cycle %d", cc);
            $finish;
        end
    endrule

    rule cc_rule;
        cc <= cc + 1;
    endrule

    method Action put(Int#(32) input_port, ChannelMessage msg);
        input_fifo.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        $error("Printer does not support get");
        return ?;
    endmethod
endmodule

(* synthesize *)
module mkSelectGen#(parameter String name) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    method Action put(Int#(32) input_port, ChannelMessage msg);
        input_fifo.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        let msg = output_fifo.first;
        output_fifo.deq;
        return msg;
    endmethod
endmodule 

(* synthesize *)
module mkReshape#(int in_dim, int out_dim) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    method Action put(Int#(32) input_port, ChannelMessage msg);
        input_fifo.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        output_fifo.deq;
        return output_fifo.first;
    endmethod
endmodule

(* synthesize *)
module mkDynOffChipLoad#(parameter String addr, Bool pred) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    method Action put(Int#(32) input_port, ChannelMessage msg);
        input_fifo.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        output_fifo.deq;
        return output_fifo.first;
    endmethod
endmodule

(* synthesize *)
module mkTiledRetileStreamify#(Int#(32) repeats, Bool filter_mask, Bool split_row) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    method Action put(Int#(32) input_port, ChannelMessage msg);
        input_fifo.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        output_fifo.deq;
        return output_fifo.first;
    endmethod
endmodule

(* synthesize *)
module mkReassemble#(Int#(32) num_inputs) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    method Action put(Int#(32) input_port, ChannelMessage msg);
        input_fifo.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        output_fifo.deq;
        return output_fifo.first;
    endmethod
endmodule

module mkBroadcastTest (Empty);
    Broadcast_IFC#(5) bc <- mkBroadcast(5);

    Reg#(Int#(32)) i <- mkReg(0);

    let fsm <- mkAutoFSM(
        par
        action
            bc.op.put(0, tagged Tag_Data tuple2(tagged Tag_Tile unpack(0), 0));
            $display("Put tile with ref 0");
        endaction 
        for (i <= 0; i < 5; i <= i + 1) 
            action
                let t <- bc.op.get(i);
                if (t matches tagged Tag_Data .td &&& tpl_2(td) == 0) begin
                    $display("Received tile with ref 0 from port %d", i);
                end else begin
                    $display("Error: Expected tile with ref 0, got %s", fshow(t));
                    $finish(-1);
                end 
            endaction
        endpar
    );

endmodule
endpackage