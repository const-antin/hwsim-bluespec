package Operation;

import FIFOF::*;
import FIFO::*;
import Vector::*;
import Assert::*;
import Types::*;
import FileReader::*;
import RamulatorArbiter::*;
import StmtFSM::*;

function Bit#(m) resize(Bit#(n) x);
    // TMax#(m,n) is a type‐level max(m,n)
    Bit#(TMax#(m,n)) x_ext = zeroExtend(x);
    Bit#(m)            y   = truncate(x_ext);
    return y;
endfunction

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

interface Partition_IFC#(numeric type num_outputs);
    interface Operation_IFC op;
endinterface

module mkPartition#(Int#(32) rank, Integer num_outputs) (Partition_IFC#(num_outputs));
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) sel_fifo <- mkFIFO;
    Vector#(num_outputs, FIFO#(ChannelMessage)) output_fifo <- replicateM(mkFIFO);

    Reg#(Int#(32)) count <- mkReg(0);

    rule propagate_end if (input_fifo.first matches tagged Tag_EndToken);
        input_fifo.deq;
        if (sel_fifo.first matches tagged Tag_EndToken) begin
            sel_fifo.deq;
        end else begin
            $display("Error: Expected end token in select FIFO, got", fshow(sel_fifo.first));
            $finish(-1);
        end
        for (Int#(32) i = 0; i < fromInteger(num_outputs); i = i + 1) begin
            output_fifo[i].enq(tagged Tag_EndToken);
        end
    endrule

    rule do_partition if (input_fifo.first matches tagged Tag_Data .current &&& sel_fifo.first matches tagged Tag_Data .selected);
        for (Int#(32) i = 0; i < fromInteger(num_outputs); i = i + 1) begin    
            if (tpl_1(selected).Tag_Selector[i] == 1) begin
                output_fifo[i].enq(tagged Tag_Data tuple2(tpl_1(current), tpl_2(current)));
            end
        end
        input_fifo.deq;
        sel_fifo.deq;
    endrule

    interface Operation_IFC op;
        method Action put(Int#(32) input_port, ChannelMessage msg);
            if (input_port == 0) begin
                input_fifo.enq(msg);
            end else begin
                sel_fifo.enq(msg);
            end
        endmethod

        method ActionValue#(ChannelMessage) get(Int#(32) output_port);
            output_fifo[output_port].deq;
            return output_fifo[output_port].first;
        endmethod
    endinterface
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

module mkAccumRetile#(Int#(32) rank) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    Reg#(Tile) acc <- mkReg(0);
    Reg#(UInt#(TAdd#(TLog#(TMul#(TILE_SIZE, SizeOf#(Scalar))), 1))) col_ptr <- mkReg(0);

    rule concat if (input_fifo.first matches tagged Tag_Data .current);
        input_fifo.deq;
        let shift = (valueOf(SizeOf#(Scalar)) * valueOf(TILE_SIZE));
        let novel = tpl_1(current).Tag_Tile << (fromInteger(shift) * col_ptr);
        let newtile = acc | novel;

        if (col_ptr + 1 == fromInteger(valueOf(TILE_SIZE)) || tpl_2(current) >= rank) begin
            // The tile is full, we def' have to emit it.
            if (tpl_2(current) < rank) begin
                $display("Received new tile to accumulate, but tile already is bigger than hardware tile size!");
                $finish(-1);
            end
            col_ptr <= 0;
            acc <= 0;
            let out_rank = tpl_2(current) - rank;
            output_fifo.enq(tagged Tag_Data tuple2(tagged Tag_Tile newtile, out_rank));
        end else begin
            col_ptr <= col_ptr + 1;
            acc <= newtile;
        end 
    endrule

    rule forward_end if (input_fifo.first matches tagged Tag_EndToken);
        input_fifo.deq;
        output_fifo.enq(tagged Tag_EndToken);
    endrule

    method Action put(Int#(32) input_port, ChannelMessage msg);
        input_fifo.enq(msg);
    endmethod 

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        output_fifo.deq;
        return output_fifo.first;
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
        
        $display("[cycle %d] %s: ", cc, name, fshow(cur));

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
module mkReshape#(StopToken rank, Int#(32) chunk_size) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    Reg#(Int#(32)) count_this_rank <- mkReg(0);

    rule reshape if (input_fifo.first matches tagged Tag_Data .current);
        let st = tpl_2(current);
        input_fifo.deq();

        if (st < rank) begin
            output_fifo.enq(input_fifo.first);
        end else if (st == rank) begin
            let new_rank = count_this_rank + 1;
            if (new_rank == chunk_size) begin
                st = st + 1;
                count_this_rank <= 0;
                output_fifo.enq(tagged Tag_Data tuple2(tpl_1(current), st));
            end else begin
                count_this_rank <= new_rank;
                output_fifo.enq(input_fifo.first);
            end 
        end else if (st > rank) begin
            let new_rank = count_this_rank + 1;
            if (new_rank == chunk_size) begin
                output_fifo.enq(tagged Tag_Data tuple2(tpl_1(current), st + 1));
                count_this_rank <= 0;
            end else begin 
                $display("Error: Reshape would have to pad values.");
                $finish(-1);
            end 
        end 
    endrule

    rule pass_end if (input_fifo.first matches tagged Tag_EndToken);
        input_fifo.deq;
        output_fifo.enq(tagged Tag_EndToken);
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

    Reg#(UInt#(TAdd#(TLog#(TILE_SIZE), 1))) col_idx <- mkReg(0);

    rule retile if (input_fifo.first matches tagged Tag_Data .current);
        StopToken rank;
        if (col_idx < fromInteger(valueOf(TILE_SIZE)) - 1) begin
            rank = 0;
        end else begin
            rank = tpl_2(current) + 1; // TODO: I assume the rank should be incremented here.
        end
    
        if (col_idx < fromInteger(valueOf(TILE_SIZE))) begin
            let data_width = fromInteger(valueOf(SizeOf#(Scalar)) * valueOf(TILE_SIZE));
            Vector#(TILE_SIZE, Bit#(TMul#(TILE_SIZE, SizeOf#(Scalar)))) rows = unpack(pack(tpl_1(current).Tag_Tile));
            let row = rows[col_idx];
            let tile = tagged Tag_Tile pack(extend(row));
            ChannelMessage out = tagged Tag_Data tuple2(tile, rank);
            output_fifo.enq(out);
        end
        if (col_idx + 1 == fromInteger(valueOf(TILE_SIZE))) begin
            col_idx <= 0;
            input_fifo.deq;
        end else begin
            col_idx <= col_idx + 1;
        end 
        if (col_idx + 1 > fromInteger(valueOf(TILE_SIZE))) begin
            $finish(-1);
        end
    endrule

    rule pass_end if (input_fifo.first matches tagged Tag_EndToken);
        input_fifo.deq;
        output_fifo.enq(tagged Tag_EndToken);
    endrule

    method Action put(Int#(32) input_port, ChannelMessage msg);
        input_fifo.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get(Int#(32) output_port);
        output_fifo.deq;
        return output_fifo.first;
    endmethod
endmodule

interface Reassemble_IFC#(numeric type num_inputs);
    interface Operation_IFC op;
endinterface

// TODO: This is not II=1 yet.
module mkReassemble#(Integer num_inputs) (Reassemble_IFC#(num_inputs));
    Vector#(num_inputs, FIFOF#(ChannelMessage)) input_fifos <- replicateM(mkFIFOF);
    FIFO#(ChannelMessage) sel_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    Reg#(Selector) this_selector <- mkReg(0);

    Wire#(UInt#(TLog#(num_inputs))) first_to_dequeue <- mkWire;
    Wire#(Selector) current_selector <- mkWire;

    function has_data_and_is_selected(x) = (tpl_1(x).notEmpty && tpl_2(x) == 1);
    function id(x) = x;

    rule get_selector if (sel_fifo.first matches tagged Tag_Data .selected &&& this_selector == 0);
        this_selector <= tpl_1(selected).Tag_Selector;
        sel_fifo.deq;
    endrule

    rule find_reassemble if (this_selector != 0);
        let t = resize(pack(this_selector));
        Vector#(num_inputs, Bit#(1)) select_as_vec = unpack(t);
        let is_selected = map(has_data_and_is_selected, zip(input_fifos, select_as_vec));
        let dequeue_idx = findIndex(id, is_selected);
        if (dequeue_idx matches tagged Valid .index) begin
            first_to_dequeue <= index;
        end
    endrule

    rule do_reassemble;
        let this_selector_updated = this_selector;
        this_selector_updated[first_to_dequeue] = 0; // Clear the selector for the dequeued input
        this_selector <= this_selector_updated;

        output_fifo.enq(input_fifos[first_to_dequeue].first);
        input_fifos[first_to_dequeue].deq;
    endrule

    rule do_end if (sel_fifo.first matches tagged Tag_EndToken &&& this_selector == 0);
        sel_fifo.deq;
        for (Int#(32) i = 0; i < fromInteger(num_inputs); i = i + 1) begin
            input_fifos[i].deq;
        end
        output_fifo.enq(tagged Tag_EndToken);
    endrule

    interface Operation_IFC op;
        method Action put(Int#(32) input_port, ChannelMessage msg);
            if (input_port < fromInteger(num_inputs)) begin
                input_fifos[input_port].enq(msg);
            end else if (input_port == fromInteger(num_inputs)) begin
                sel_fifo.enq(msg);
            end else begin
                $display("Reassemble: Invalid put index", fshow(input_port));
                $finish(-1);
            end 
        endmethod

        method ActionValue#(ChannelMessage) get(Int#(32) output_port);
            output_fifo.deq;
            return output_fifo.first;
        endmethod
    endinterface
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
                    $display("Error: Expected tile with ref 0, got ", fshow(t));
                    $finish(-1);
                end 
            endaction
        endpar
    );
endmodule

module mkAccumRetileTest (Empty);
    Operation_IFC op <- mkAccumRetile(1);

    let tile_a = tagged Tag_Tile unpack(5);
    let tile_b = tagged Tag_Tile unpack(1);
    let tile_ref = tagged Tag_Tile (tile_a.Tag_Tile | (tile_b.Tag_Tile << (valueOf(SizeOf#(Scalar)) * valueOf(TILE_SIZE))));

    let msg_a = tagged Tag_Data tuple2(tile_a, 0);
    let msg_b = tagged Tag_Data tuple2(tile_b, 1);
    let msg_ref = tagged Tag_Data tuple2(tile_ref, 0);

    mkAutoFSM(
        par
            seq
                action
                    op.put(0, msg_a);
                endaction
                action
                    op.put(0, msg_b);
                endaction
                action
                    op.put(0, msg_a);
                endaction
                action
                    op.put(0, msg_b);
                endaction
            endseq
            action
                let t <- op.get(0);
                if (t != msg_ref) begin
                    $display("Return did not match reference! Got ", fshow(t), ", expected ", fshow(msg_ref));
                    $finish(-1);
                end
            endaction
            action
                let t <- op.get(0);
                if (t != msg_ref) begin
                    $display("Return did not match reference! Got ", fshow(t), ", expected ", fshow(msg_ref));
                    $finish(-1);
                end
                $display("SUCCESS!");
            endaction
        endpar
    );
endmodule

module mkReassembleTest (Empty);
    Reassemble_IFC#(4) reassemble <- mkReassemble(4);

    mkAutoFSM (
        par
            seq
                action
                    reassemble.op.put(1, tagged Tag_Data tuple2(Tag_Tile(unpack(1)), 0));
                    reassemble.op.put(4, tagged Tag_Data tuple2(Tag_Selector(unpack(2)), 0));
                    $display("put first round");
                endaction

                action
                    reassemble.op.put(0, tagged Tag_Data tuple2(Tag_Tile(unpack(1)), 0));
                    reassemble.op.put(1, tagged Tag_Data tuple2(Tag_Tile(unpack(2)), 0));
                    reassemble.op.put(4, tagged Tag_Data tuple2(Tag_Selector(unpack(3)), 0));
                    $display("put second round");
                endaction
            endseq
            seq 
                action
                    let t <- reassemble.op.get(0);
                    $display("t (0):", fshow(tpl_1(t.Tag_Data).Tag_Tile[2:0]));
                endaction
                action 
                    let t <- reassemble.op.get(0);
                    $display("t (0):", fshow(tpl_1(t.Tag_Data).Tag_Tile[2:0]));
                endaction 
                action
                    let t <- reassemble.op.get(0);
                    $display("t (1):", fshow(tpl_1(t.Tag_Data).Tag_Tile[2:0]));
                endaction
            endseq 
        endpar 
    );
endmodule

module mkPartitionTest (Empty);
    Partition_IFC#(4) partition <- mkPartition(2, 4);

    mkAutoFSM (
        par
            seq
                action
                    partition.op.put(0, tagged Tag_Data tuple2(Tag_Tile(unpack(1)), 0));
                    partition.op.put(1, tagged Tag_Data tuple2(Tag_Selector(unpack(2)), 0));
                    $display("put first round");
                endaction

                action
                    partition.op.put(0, tagged Tag_Data tuple2(Tag_Tile(unpack(1)), 0));
                    partition.op.put(1, tagged Tag_Data tuple2(Tag_Selector(unpack(3)), 0));
                    $display("put second round");
                endaction
            endseq
            seq
                action
                    let t <- partition.op.get(1);
                    $display("t (1):", fshow(tpl_1(t.Tag_Data).Tag_Tile[2:0]));
                endaction
                action
                    let t <- partition.op.get(0);
                    $display("t (0):", fshow(tpl_1(t.Tag_Data).Tag_Tile[2:0]));
                endaction
                action
                    let t <- partition.op.get(1);
                    $display("t (1):", fshow(tpl_1(t.Tag_Data).Tag_Tile[2:0]));
                endaction
            endseq 
        endpar
    );
endmodule

module mkTiledRetileStreamifyTest (Empty);
    Operation_IFC retile <- mkTiledRetileStreamify(2, True, True);

    Reg#(Int#(32)) i <- mkReg(0);
    let data = tagged Tag_Data tuple2(Tag_Tile(unpack(0)), 8);

    mkAutoFSM (
        par
            seq
                action
                    retile.put(0, data);
                endaction
                action
                    retile.put(0, tagged Tag_EndToken);
                endaction 
            endseq
            seq
                for (i <= 0; i < fromInteger(valueOf(TILE_SIZE)); i <= i + 1) 
                    action
                        let t <- retile.get(0);
                        $display("tile: ", fshow(t));
                    endaction
                action
                    let t <- retile.get(0);
                    if (t != tagged Tag_EndToken) begin
                        $display("Expected end token, got", fshow(t));
                        $finish(-1);
                    end else begin
                        $display("Received end token as expected");
                    end
                endaction
            endseq
        endpar
    );
endmodule

endpackage