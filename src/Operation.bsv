package Operation;

import FIFOF::*;
import FIFO::*;
import Vector::*;
import Assert::*;
import Types::*;
import FileReader::*;
import RamulatorArbiter::*;
import ALU::*;
import Instructions::*;

// Function to map ALUOp to tile operation
function Tile apply_alu_op(ALUOp op, Tile a, Tile b);
    Tile result;
    case (op) matches
        ADD: result = add_tile(a, b);
        SUB: result = sub_tile(a, b);
        MUL: result = mul_tile(a, b);
        DIV: result = div_tile(a, b);
        MATMUL_T: result = matmul_t_tile(a, b);
        // MATMUL: result = matmul_tile(a, b); // Disabled as requested
        MATMUL: begin
            let t = $error("MATMUL not implemented");
            result = a;
        end
        default: result = a; // Default to identity
    endcase
    return result;
endfunction

function Tile apply_alu_op_unary(ALUOp op, Tile a);
    Tile result;
    case (op) matches
        // For unary operations, we'll need to add specific cases
        // For now, return the input tile
        default: result = a;
    endcase
    return result;
endfunction

interface Operation_IFC;
    method Action put(UInt#(32) input_port, ChannelMessage msg);
    method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
endinterface

interface Accum_IFC;
    interface Operation_IFC op;
    method Action set_cfg(AccumulateConfig cfg);
endinterface

module mkAccum#(ALU_IFC alu) (Accum_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;
    Reg#(AccumulateConfig) cfg <- mkReg(AccumulateConfig{op: ADD, rank: 0, init: 0});

    Reg#(Maybe#(Tile)) acc <- mkReg(tagged Invalid);

    rule do_accum if (input_fifo.first matches tagged Tag_Data .current);
        input_fifo.deq;

        let data = tpl_1(current);
        let st = tpl_2(current);

        Tile out;
        if (acc matches tagged Valid .tile) begin
            let tile2 = data.Tag_Tile;
            out = apply_alu_op(cfg.op, tile, tile2);
        end else begin
            out = data.Tag_Tile;
        end

        if (st >= cfg.rank) begin 
            let out_rank = st - cfg.rank;
            acc <= tagged Invalid;
            output_fifo.enq(tagged Tag_Data tuple2(tagged Tag_Tile out, out_rank));
        end else begin
            acc <= tagged Valid out;
        end

    endrule

    method Action set_cfg(AccumulateConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            input_fifo.enq(msg);
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            output_fifo.deq;
            return output_fifo.first;
        endmethod
    endinterface
endmodule

interface RepeatStatic_IFC;
    interface Operation_IFC op;
    method Action set_cfg(RepeatStaticConfig cfg);
endinterface

module mkRepeatStatic (RepeatStatic_IFC);
    Reg#(RepeatStaticConfig) cfg <- mkReg(RepeatStaticConfig{count: 0});

    FIFOF#(ChannelMessage) input_fifo <- mkFIFOF;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    Reg#(UInt#(16)) count <- mkReg(0);

    rule do_repeat if (count < cfg.count);
        let cur = input_fifo.first;

        if (cur matches tagged Tag_Data .current) begin
            Data to_send = tpl_1(current);
            if (count == cfg.count - 1) begin
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

    rule dequeue if (count == cfg.count);
        input_fifo.deq;
        count <= 0;
    endrule

    method Action set_cfg(RepeatStaticConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            input_fifo.enq(msg);
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            output_fifo.deq;
            return output_fifo.first;
        endmethod
    endinterface
endmodule

interface UnaryMap_IFC;
    interface Operation_IFC op;
    method Action set_cfg(UnaryMapConfig cfg);
endinterface

module mkUnaryMap#(ALU_IFC alu) (UnaryMap_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    Reg#(UnaryMapConfig) cfg <- mkReg(UnaryMapConfig{op: ADD});

    rule do_map;
        let cur = input_fifo.first;
        input_fifo.deq;

        if (cur matches tagged Tag_Data .current) begin 
            let out = apply_alu_op_unary(cfg.op, tpl_1(current).Tag_Tile);
            output_fifo.enq(tagged Tag_Data tuple2(tagged Tag_Tile out, tpl_2(current)));
        end
    endrule

    method Action set_cfg(UnaryMapConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            input_fifo.enq(msg);
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            output_fifo.deq;
            return output_fifo.first;
        endmethod
    endinterface
endmodule

interface BinaryMap_IFC;
    interface Operation_IFC op;
    method Action set_cfg(BinaryMapConfig cfg);
endinterface

module mkBinaryMap#(ALU_IFC alu) (BinaryMap_IFC);
    FIFO#(ChannelMessage) input_fifo1 <- mkFIFO;
    FIFO#(ChannelMessage) input_fifo2 <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;
    Reg#(BinaryMapConfig) cfg <- mkReg(BinaryMapConfig{op: ADD});
    Reg#(Int#(32)) count <- mkReg(0);

    rule do_map;
        let cur_1 = input_fifo1.first;
        let cur_2 = input_fifo2.first;

        input_fifo1.deq;
        input_fifo2.deq;

        if (cur_1 matches tagged Tag_Data .current_1 &&& cur_2 matches tagged Tag_Data .current_2) begin
            let out = apply_alu_op(cfg.op, tpl_1(current_1).Tag_Tile, tpl_1(current_2).Tag_Tile);
            // $display("ST1: %d, ST2: %d, count: %d", tpl_2(current_1), tpl_2(current_2), count);
            if (tpl_2(current_2) != tpl_2(current_1)) begin
                $error("Map: Stop tokens are not the same, left: %d, right: %d", tpl_2(current_1), tpl_2(current_2));
                $finish;
                // $finish;
            end
            // dynamicAssert(tpl_2(current_2) == tpl_2(current_1), "Stop tokens must be the same");
            output_fifo.enq(tagged Tag_Data tuple2(tagged Tag_Tile out, tpl_2(current_1)));
            count <= count + 1;
        end
    endrule

    method Action set_cfg(BinaryMapConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            if (input_port == 0) begin
                input_fifo1.enq(msg);
            end else begin
                input_fifo2.enq(msg);
            end
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            output_fifo.deq;
            return output_fifo.first;
        endmethod
    endinterface
endmodule

interface Promote_IFC;
    interface Operation_IFC op;
    method Action set_cfg(PromoteConfig cfg);
endinterface

module mkPromote (Promote_IFC);
    Reg#(PromoteConfig) cfg <- mkReg(PromoteConfig{rank: 0});
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    rule do_promote;
        let cur = input_fifo.first;
        input_fifo.deq;

        if (cur matches tagged Tag_Data .current) begin
            let data = tpl_1(current);
            let st = tpl_2(current);
            let st_out = (st >= cfg.rank) ? st + 1 : st;
            output_fifo.enq(tagged Tag_Data tuple2(data, st_out));
        end else begin 
            output_fifo.enq(cur);
        end
    endrule

    method Action set_cfg(PromoteConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            input_fifo.enq(msg);
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            output_fifo.deq;
            return output_fifo.first;
        endmethod
    endinterface
endmodule

typedef enum {
    AccumBigTile_Fill,
    AccumBigTile_Accum,
    AccumBigTile_Drain
} AccumBigTileState deriving (Bits, Eq, FShow);

interface AccumBigTile_IFC;
    interface Operation_IFC op;
    method Action set_cfg(AccumulateBigTileConfig cfg);
endinterface

module mkAccumBigTile#(ALU_IFC alu) (AccumBigTile_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) partial_input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) partial_output_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    Reg#(AccumBigTileState) state <- mkReg(AccumBigTile_Fill);
    Reg#(AccumulateBigTileConfig) cfg <- mkReg(AccumulateBigTileConfig{op: ADD, rank: 0});
    
    rule fill if (state == AccumBigTile_Fill);
        let cur = input_fifo.first;
        input_fifo.deq;
        
        let st = tpl_2(cur.Tag_Data);
        partial_output_fifo.enq(cur);

        if (st >= cfg.rank) begin
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
        let out = apply_alu_op(cfg.op, tpl_1(add.Tag_Data).Tag_Tile, tpl_1(acc.Tag_Data).Tag_Tile);

        if (st >= cfg.rank) begin 
            state <= AccumBigTile_Drain;
        end 

        partial_output_fifo.enq(tagged Tag_Data tuple2(tagged Tag_Tile out, st));
    endrule

    rule drain if (state == AccumBigTile_Drain);
        let cur_in = partial_input_fifo.first;
        partial_input_fifo.deq;

        let data = cur_in.Tag_Data;
        let st = tpl_2(data);

        StopToken out_st;
        if (st >= cfg.rank) begin
            out_st = st - cfg.rank + 2;
        end else begin 
            out_st = st;
        end

        if (st >= cfg.rank) begin
            state <= AccumBigTile_Fill;
        end

        output_fifo.enq(tagged Tag_Data tuple2(tpl_1(data), out_st));
    endrule
    
    method Action set_cfg(AccumulateBigTileConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            if (input_port == 0) begin
                input_fifo.enq(msg);
            end else begin
                partial_input_fifo.enq(msg);
            end
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            if (output_port == 0) begin
                partial_output_fifo.deq;
                return partial_output_fifo.first;
            end else begin
                output_fifo.deq;
                return output_fifo.first;
            end
        endmethod
    endinterface
endmodule

module mkTileReader#(Integer num_entries, String filename, Bit#(8) port_id, RamulatorArbiterIO arbiter) (Operation_IFC);
    FileReader_IFC#(TaggedTile) reader <- mkFileReader(num_entries, filename, port_id, arbiter);
    
    method Action put(UInt#(32) input_port, ChannelMessage msg);
        $error("TileReader does not support put");
    endmethod

    method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
        TaggedTile tile <- reader.readNext;
        return tagged Tag_Data tuple2(tagged Tag_Tile tile.t, tile.st);
    endmethod 
endmodule

// Stub modules for missing operations

interface Broadcast_IFC;
    interface Operation_IFC op;
    method Action set_cfg(BroadcastConfig cfg);
endinterface

module mkBroadcast (Broadcast_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo1 <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo2 <- mkFIFO;
    Reg#(BroadcastConfig) cfg <- mkReg(BroadcastConfig{});

    rule do_broadcast;
        let cur = input_fifo.first;
        input_fifo.deq;
        
        if (cur matches tagged Tag_EndToken .end_token) begin
            output_fifo1.enq(cur);
            output_fifo2.enq(cur);
        end else begin
            output_fifo1.enq(cur);
            output_fifo2.enq(cur);
        end
    endrule

    method Action set_cfg(BroadcastConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            input_fifo.enq(msg);
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            if (output_port == 0) begin
                output_fifo1.deq;
                return output_fifo1.first;
            end else begin
                output_fifo2.deq;
                return output_fifo2.first;
            end
        endmethod
    endinterface
endmodule

interface Concat_IFC;
    interface Operation_IFC op;
    method Action set_cfg(ConcatConfig cfg);
endinterface

module mkConcat (Concat_IFC);
    FIFO#(ChannelMessage) input_fifo1 <- mkFIFO;
    FIFO#(ChannelMessage) input_fifo2 <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;
    Reg#(ConcatConfig) cfg <- mkReg(ConcatConfig{rank: 0});
    Reg#(Bool) reading_left <- mkReg(True);

    rule do_concat;
        let cur_input = reading_left ? input_fifo1.first : input_fifo2.first;
        
        if (cur_input matches tagged Tag_Data .current) begin
            let data = tpl_1(current);
            let st = tpl_2(current);
            
            if (st == cfg.rank) begin
                reading_left <= !reading_left;
            end
            
            output_fifo.enq(tagged Tag_Data tuple2(data, st));
        end else if (cur_input matches tagged Tag_EndToken .end_token) begin
            output_fifo.enq(cur_input);
            
            // Get the other input's end token
            if (reading_left) begin
                if (input_fifo2.first matches tagged Tag_EndToken .end_token_2) begin
                    input_fifo2.deq;
                end
            end else begin
                if (input_fifo1.first matches tagged Tag_EndToken .end_token_1) begin
                    input_fifo1.deq;
                end
            end
        end
        
        if (reading_left) begin
            input_fifo1.deq;
        end else begin
            input_fifo2.deq;
        end
    endrule

    method Action set_cfg(ConcatConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            if (input_port == 0) begin
                input_fifo1.enq(msg);
            end else begin
                input_fifo2.enq(msg);
            end
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            output_fifo.deq;
            return output_fifo.first;
        endmethod
    endinterface
endmodule

interface Enumerate_IFC;
    interface Operation_IFC op;
    method Action set_cfg(EnumerateConfig cfg);
endinterface

module mkEnumerate (Enumerate_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo1 <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo2 <- mkFIFO;
    Reg#(EnumerateConfig) cfg <- mkReg(EnumerateConfig{rank: 0});
    Reg#(Int#(32)) counter <- mkReg(0);

    rule do_enumerate;
        let cur = input_fifo.first;
        input_fifo.deq;
        
        if (cur matches tagged Tag_Data .current) begin
            let data = tpl_1(current);
            let st = tpl_2(current);
            
            // Output counter
            output_fifo1.enq(tagged Tag_Data tuple2(tagged Tag_Scalar counter, 0));
            // Output data
            output_fifo2.enq(tagged Tag_Data tuple2(data, st));
            
            if (st == cfg.rank) begin
                counter <= 0;
            end else begin
                counter <= counter + 1;
            end
        end else if (cur matches tagged Tag_EndToken .end_token) begin
            output_fifo1.enq(cur);
            output_fifo2.enq(cur);
        end
    endrule

    method Action set_cfg(EnumerateConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            input_fifo.enq(msg);
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            if (output_port == 0) begin
                output_fifo1.deq;
                return output_fifo1.first;
            end else begin
                output_fifo2.deq;
                return output_fifo2.first;
            end
        endmethod
    endinterface
endmodule

interface Flatten_IFC;
    interface Operation_IFC op;
    method Action set_cfg(FlattenConfig cfg);
endinterface

module mkFlatten (Flatten_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;
    Reg#(FlattenConfig) cfg <- mkReg(FlattenConfig{rank: 0});

    rule do_flatten;
        let cur = input_fifo.first;
        input_fifo.deq;
        
        if (cur matches tagged Tag_Data .current) begin
            let data = tpl_1(current);
            let st = tpl_2(current);
            
            StopToken out_st;
            if (st == cfg.rank) begin
                out_st = 0;
            end else if (st > cfg.rank) begin
                out_st = st - 1;
            end else begin
                out_st = st;
            end
            
            output_fifo.enq(tagged Tag_Data tuple2(data, out_st));
        end else if (cur matches tagged Tag_EndToken .end_token) begin
            output_fifo.enq(cur);
        end
    endrule

    method Action set_cfg(FlattenConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            input_fifo.enq(msg);
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            output_fifo.deq;
            return output_fifo.first;
        endmethod
    endinterface
endmodule

interface FlatMap_IFC;
    interface Operation_IFC op;
    method Action set_cfg(FlatMapConfig cfg);
endinterface

module mkFlatMap (FlatMap_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;
    Reg#(FlatMapConfig) cfg <- mkReg(FlatMapConfig{rank: 0});

    rule do_flatmap;
        let cur = input_fifo.first;
        input_fifo.deq;
        
        if (cur matches tagged Tag_Data .current) begin
            let data = tpl_1(current);
            let st = tpl_2(current);
            
            if (st > cfg.rank) begin
                output_fifo.enq(tagged Tag_Data tuple2(data, st - 1));
            end else if (st == cfg.rank) begin
                output_fifo.enq(tagged Tag_Data tuple2(data, 0));
            end else begin
                output_fifo.enq(tagged Tag_Data tuple2(data, st));
            end
        end else if (cur matches tagged Tag_EndToken .end_token) begin
            output_fifo.enq(cur);
        end
    endrule

    method Action set_cfg(FlatMapConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            input_fifo.enq(msg);
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            output_fifo.deq;
            return output_fifo.first;
        endmethod
    endinterface
endmodule

interface RepeatN_IFC;
    interface Operation_IFC op;
    method Action set_cfg(RepeatNConfig cfg);
endinterface

module mkRepeatN (RepeatN_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;
    Reg#(RepeatNConfig) cfg <- mkReg(RepeatNConfig{count: 0});
    
    Reg#(Maybe#(ChannelMessage)) current_data <- mkReg(tagged Invalid);
    Reg#(UInt#(32)) remaining_count <- mkReg(0);
    Reg#(Bool) repeating <- mkReg(False);

    rule do_repeat_n;
        if (!repeating) begin
            let cur = input_fifo.first;
            input_fifo.deq;
            
            if (cur matches tagged Tag_EndToken .end_token) begin
                output_fifo.enq(cur);
            end else begin
                // Output the first repetition immediately
                output_fifo.enq(cur);
                
                if (cfg.count > 1) begin
                    // Store for additional repetitions
                    current_data <= tagged Valid cur;
                    remaining_count <= cfg.count - 2; // -2 because we already output one
                    repeating <= True;
                end
            end
        end else begin
            let data = current_data.Valid;
            
            if (remaining_count == 0) begin
                // Last repetition - increment stop token
                if (data matches tagged Tag_Data .current) begin
                    let msg_data = tpl_1(current);
                    let st = tpl_2(current);
                    output_fifo.enq(tagged Tag_Data tuple2(msg_data, st + 1));
                end
                current_data <= tagged Invalid;
                repeating <= False;
            end else begin
                // Not last repetition - keep stop token at 0
                if (data matches tagged Tag_Data .current) begin
                    let msg_data = tpl_1(current);
                    output_fifo.enq(tagged Tag_Data tuple2(msg_data, 0));
                end
                remaining_count <= remaining_count - 1;
            end
        end
    endrule

    method Action set_cfg(RepeatNConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            input_fifo.enq(msg);
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            output_fifo.deq;
            return output_fifo.first;
        endmethod
    endinterface
endmodule

interface RepeatRef_IFC;
    interface Operation_IFC op;
    method Action set_cfg(RepeatRefConfig cfg);
endinterface

module mkRepeatRef (RepeatRef_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) ref_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;
    Reg#(RepeatRefConfig) cfg <- mkReg(RepeatRefConfig{rank: 0});

    rule do_repeat_ref;
        let cur_in = input_fifo.first;
        let cur_ref = ref_fifo.first;
        
        if (cur_ref matches tagged Tag_Data .ref_data) begin
            let ref_st = tpl_2(ref_data);
            
            if (cur_in matches tagged Tag_Data .in_data) begin
                let in_st = tpl_2(in_data);
                
                if (in_st > 0) begin
                    // Assert in_st + rank == ref_st
                    if (in_st + cfg.rank == ref_st) begin
                        output_fifo.enq(tagged Tag_Data tuple2(tpl_1(in_data), ref_st));
                    end
                end else begin
                    output_fifo.enq(tagged Tag_Data tuple2(tpl_1(in_data), ref_st));
                end
                
                if (ref_st >= cfg.rank) begin
                    input_fifo.deq;
                    ref_fifo.deq;
                end else begin
                    ref_fifo.deq;
                end
            end else if (cur_in matches tagged Tag_EndToken .end_token) begin
                output_fifo.enq(cur_in);
                input_fifo.deq;
                ref_fifo.deq;
            end
        end else if (cur_ref matches tagged Tag_EndToken .end_token) begin
            if (cur_in matches tagged Tag_EndToken .end_token_2) begin
                output_fifo.enq(cur_ref);
                input_fifo.deq;
                ref_fifo.deq;
            end
        end
    endrule

    method Action set_cfg(RepeatRefConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            if (input_port == 0) begin
                input_fifo.enq(msg);
            end else begin
                ref_fifo.enq(msg);
            end
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            output_fifo.deq;
            return output_fifo.first;
        endmethod
    endinterface
endmodule

interface Reshape_IFC;
    interface Operation_IFC op;
    method Action set_cfg(ReshapeConfig cfg);
endinterface

module mkReshape (Reshape_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;
    Reg#(ReshapeConfig) cfg <- mkReg(ReshapeConfig{});

    rule do_reshape;
        let cur = input_fifo.first;
        input_fifo.deq;
        
        // For now, just pass through the data
        // TODO: Implement actual reshape logic
        output_fifo.enq(cur);
    endrule

    method Action set_cfg(ReshapeConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            input_fifo.enq(msg);
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            output_fifo.deq;
            return output_fifo.first;
        endmethod
    endinterface
endmodule

interface Reassemble_IFC;
    interface Operation_IFC op;
    method Action set_cfg(ReassembleConfig cfg);
endinterface

module mkReassemble (Reassemble_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;
    Reg#(ReassembleConfig) cfg <- mkReg(ReassembleConfig{rank: 0});

    rule do_reassemble;
        let cur = input_fifo.first;
        input_fifo.deq;
        
        // For now, just pass through the data
        // TODO: Implement actual reassemble logic
        output_fifo.enq(cur);
    endrule

    method Action set_cfg(ReassembleConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            input_fifo.enq(msg);
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            output_fifo.deq;
            return output_fifo.first;
        endmethod
    endinterface
endmodule

interface Rotate_IFC;
    interface Operation_IFC op;
    method Action set_cfg(RotateConfig cfg);
endinterface

module mkRotate (Rotate_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo1 <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo2 <- mkFIFO;
    Reg#(RotateConfig) cfg <- mkReg(RotateConfig{reset_rank: 0});
    Reg#(Int#(32)) current_output <- mkReg(0);

    rule do_rotate;
        let cur = input_fifo.first;
        input_fifo.deq;
        
        if (cur matches tagged Tag_Data .current) begin
            let data = tpl_1(current);
            let st = tpl_2(current);
            
            // Route to current output
            if (current_output == 0) begin
                output_fifo1.enq(tagged Tag_Data tuple2(data, st));
            end else begin
                output_fifo2.enq(tagged Tag_Data tuple2(data, st));
            end
            
            if (st < cfg.reset_rank) begin
                current_output <= (current_output + 1) % 2;
            end else begin
                current_output <= 0;
            end
        end else if (cur matches tagged Tag_EndToken .end_token) begin
            output_fifo1.enq(cur);
            output_fifo2.enq(cur);
        end
    endrule

    method Action set_cfg(RotateConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            input_fifo.enq(msg);
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            if (output_port == 0) begin
                output_fifo1.deq;
                return output_fifo1.first;
            end else begin
                output_fifo2.deq;
                return output_fifo2.first;
            end
        endmethod
    endinterface
endmodule

interface Parallelize_IFC;
    interface Operation_IFC op;
    method Action set_cfg(ParallelizeConfig cfg);
endinterface

module mkParallelize (Parallelize_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo1 <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo2 <- mkFIFO;
    Reg#(ParallelizeConfig) cfg <- mkReg(ParallelizeConfig{rank: 0});
    Reg#(Int#(32)) current_output <- mkReg(0);

    rule do_parallelize;
        let cur = input_fifo.first;
        input_fifo.deq;
        
        if (cur matches tagged Tag_Data .current) begin
            let data = tpl_1(current);
            let st = tpl_2(current);
            
            // Route to current output
            if (current_output == 0) begin
                output_fifo1.enq(tagged Tag_Data tuple2(data, st));
            end else begin
                output_fifo2.enq(tagged Tag_Data tuple2(data, st));
            end
            
            if (st < cfg.rank) begin
                // Keep same output
            end else if (st == cfg.rank) begin
                current_output <= (current_output + 1) % 2;
            end else begin
                current_output <= 0;
            end
        end else if (cur matches tagged Tag_EndToken .end_token) begin
            output_fifo1.enq(cur);
            output_fifo2.enq(cur);
        end
    endrule

    method Action set_cfg(ParallelizeConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            input_fifo.enq(msg);
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            if (output_port == 0) begin
                output_fifo1.deq;
                return output_fifo1.first;
            end else begin
                output_fifo2.deq;
                return output_fifo2.first;
            end
        endmethod
    endinterface
endmodule

interface Partition_IFC;
    interface Operation_IFC op;
    method Action set_cfg(PartitionConfig cfg);
endinterface

module mkPartition (Partition_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) select_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo1 <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo2 <- mkFIFO;
    Reg#(PartitionConfig) cfg <- mkReg(PartitionConfig{rank: 0});

    rule do_partition;
        let cur_input = input_fifo.first;
        let cur_select = select_fifo.first;
        
        if (cur_select matches tagged Tag_Data .select_data) begin
            let select_value = tpl_1(select_data);
            let select_st = tpl_2(select_data);
            
            if (cur_input matches tagged Tag_Data .input_data) begin
                let input_value = tpl_1(input_data);
                let input_st = tpl_2(input_data);
                
                // Route based on select value
                if (select_value matches tagged Tag_Scalar .scalar) begin
                    if (scalar == 0) begin
                        output_fifo1.enq(tagged Tag_Data tuple2(input_value, input_st));
                    end else begin
                        output_fifo2.enq(tagged Tag_Data tuple2(input_value, input_st));
                    end
                end
            end
        end else if (cur_select matches tagged Tag_EndToken .end_token) begin
            if (cur_input matches tagged Tag_EndToken .end_token_2) begin
                output_fifo1.enq(cur_input);
                output_fifo2.enq(cur_input);
            end
        end
        
        input_fifo.deq;
        select_fifo.deq;
    endrule

    method Action set_cfg(PartitionConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            if (input_port == 0) begin
                input_fifo.enq(msg);
            end else begin
                select_fifo.enq(msg);
            end
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            if (output_port == 0) begin
                output_fifo1.deq;
                return output_fifo1.first;
            end else begin
                output_fifo2.deq;
                return output_fifo2.first;
            end
        endmethod
    endinterface
endmodule

interface Scan_IFC;
    interface Operation_IFC op;
    method Action set_cfg(ScanConfig cfg);
endinterface

module mkScan (Scan_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;
    Reg#(ScanConfig) cfg <- mkReg(ScanConfig{op: ADD, init: tagged Invalid, rank: 0});

    // TODO: Implement scan logic
    // rule do_scan;
    //     let cur = input_fifo.first;
    //     input_fifo.deq;
    //     output_fifo.enq(cur);
    // endrule

    method Action set_cfg(ScanConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            input_fifo.enq(msg);
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            output_fifo.deq;
            return output_fifo.first;
        endmethod
    endinterface
endmodule

interface SpatialMatmulT_IFC;
    interface Operation_IFC op;
    method Action set_cfg(SpatialMatmulTConfig cfg);
endinterface

module mkSpatialMatmulT (SpatialMatmulT_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) weight_fifo <- mkFIFO;
    FIFO#(ChannelMessage) psum_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;
    FIFO#(ChannelMessage) weight_out_fifo <- mkFIFO;
    FIFO#(ChannelMessage) input_out_fifo <- mkFIFO;
    Reg#(SpatialMatmulTConfig) cfg <- mkReg(SpatialMatmulTConfig{row_position: 0, num_rows: 0, bottom_right: False});

    rule do_spatial_matmul_t;
        // TODO: Implement spatial matmul logic
        // This is complex and would need careful implementation
        let cur = input_fifo.first;
        input_fifo.deq;
        output_fifo.enq(cur);
    endrule

    method Action set_cfg(SpatialMatmulTConfig cfg_in);
        cfg <= cfg_in;
    endmethod

    interface Operation_IFC op;
        method Action put(UInt#(32) input_port, ChannelMessage msg);
            if (input_port == 0) begin
                input_fifo.enq(msg);
            end else if (input_port == 1) begin
                weight_fifo.enq(msg);
            end else begin
                psum_fifo.enq(msg);
            end
        endmethod

        method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
            if (output_port == 0) begin
                output_fifo.deq;
                return output_fifo.first;
            end else if (output_port == 1) begin
                weight_out_fifo.deq;
                return weight_out_fifo.first;
            end else begin
                input_out_fifo.deq;
                return input_out_fifo.first;
            end
        endmethod
    endinterface
endmodule

module mkPrinter#(String name) (Operation_IFC);
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

    method Action put(UInt#(32) input_port, ChannelMessage msg);
        input_fifo.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get(UInt#(32) output_port);
        $error("Printer does not support get");
        return ?;
    endmethod
endmodule

module mkTop(Empty);
    let m1 <- mkBinaryMap(1, matmul_t_tile);
    let m2 <- mkBinaryMap(2, matmul_t_tile);

    let a1 <- mkAccum(add_tile, 1);
    let a2 <- mkAccum(add_tile, 1);

    let m3 <- mkBinaryMap(3, mul_tile);
    let m4 <- mkUnaryMap(silu_tile);

    let p5 <- mkPromote(0);

    let m6 <- mkBinaryMap(4, matmul_t_tile);
    let a7 <- mkAccum(add_tile, 1);

    rule stimulus;
        let tile = 5;
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

endpackage