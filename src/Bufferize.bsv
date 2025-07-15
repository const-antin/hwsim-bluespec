import Vector::*;
import FIFO::*;
import FIFOF::*;
import Types::*;
import Operation::*;
import RegFile::*;

function Bit#(m) resize(Bit#(n) x);
    // TMax#(m,n) is a type‐level max(m,n)
    Bit#(TMax#(m,n)) x_ext = zeroExtend(x);
    Bit#(m)            y   = truncate(x_ext);
    return y;
endfunction

typedef TMul#(TILE_SIZE, TILE_SIZE) SIZE_PER_ENTRY;

interface Bufferize#(numeric type num_entries);
// these methods are for uniform interface w.r.t. the operation module

    interface Operation_IFC operation;

    method Action put_data(ChannelMessage msg);
    method ActionValue#(ChannelMessage) get_token();
    method Action request_token(ChannelMessage msg);
    method ActionValue#(ChannelMessage) get_data();
endinterface

module mkSimpleBufferize#(Int#(32) rank, Integer num_entries) (Bufferize#(num_entries));
    FIFOF#(ChannelMessage) input_fifo <- mkFIFOF;
    FIFOF#(ChannelMessage) output_fifo <- mkFIFOF;
    FIFOF#(ChannelMessage) token_request_fifo <- mkFIFOF;    
    FIFOF#(ChannelMessage) token_output_fifo <- mkFIFOF;

    FIFOF#(Tuple2#(Ref, StopToken)) token_output_stage <- mkFIFOF;
    Reg#(Bool) token_output_stage_state <- mkReg(False);

    RegFile#(Bit#(TAdd#(TLog#(num_entries), TLog#(SIZE_PER_ENTRY))), Maybe#(Tuple2#(Data, StopToken))) buffer <- mkRegFile(0, fromInteger(valueOf(num_entries) - 1));

    Reg#(Vector#(num_entries, Bool)) free <- mkReg(replicate(True));

    Reg#(Bit#(TLog#(num_entries))) write_ptr <- mkReg(0);
    Reg#(Bit#(TLog#(SIZE_PER_ENTRY))) write_subptr <- mkReg(0);
    
    Reg#(Bit#(32)) read_ptr <- mkReg(0);

    (* descending_urgency = "deallocate_storage, store" *)
    rule store if (free[write_ptr] == True &&& input_fifo.first matches tagged Tag_Data { .data, .st });
        input_fifo.deq;

        Bit#(TAdd#(TLog#(num_entries), TLog#(SIZE_PER_ENTRY))) write_ptr_trunc = extend(write_ptr);
        Bit#(TAdd#(TLog#(num_entries), TLog#(SIZE_PER_ENTRY))) write_subptr_trunc = extend(write_subptr);

        let index = write_ptr_trunc << fromInteger(valueOf(TLog#(SIZE_PER_ENTRY))) | write_subptr_trunc;
        buffer.upd(index, tagged Valid (tuple2(data, st)));
        // buffer.upd([write_ptr][write_subptr] <= tagged Valid (tuple2(data, st));
        if (st >= rank) begin 
            write_ptr <= (write_ptr + 1);
            write_subptr <= 0;
            Ref r = resize(write_ptr);
            token_output_stage.enq(tuple2(r, st - rank));
            free[write_ptr] <= False;
        end else begin 
            write_subptr <= write_subptr + 1;
        end 
    endrule

    rule send_token; // We send the token + a deallocate request.
        let in = token_output_stage.first;
        
        if (token_output_stage_state == False) begin
            token_output_stage_state <= True;
            token_output_fifo.enq(tagged Tag_Data (tuple2(Tag_Ref (tpl_1(in)), tpl_2(in))));
        end else begin
            token_output_stage.deq;
            token_output_stage_state <= False;
            token_output_fifo.enq(tagged Tag_Deallocate_Storage (tpl_1(in)));
        end
    endrule 

    rule read if (token_request_fifo.first matches tagged Tag_Data { .data, .st }
    );
        if (free[data.Tag_Ref] == False) begin
            let ptr = data.Tag_Ref;

            let index = { ptr, read_ptr };
            let el = buffer.sub(resize(index));

            if ((read_ptr < fromInteger(num_entries)) &&& isValid(el) )
            begin
                let v = fromMaybe(?, el);    // pick a suitable default if you ever hit Invalid
                read_ptr <= read_ptr + 1;
                output_fifo.enq(tagged Tag_Data v);
            end else begin
                read_ptr <= 0;
                token_request_fifo.deq;
            end
        end
        
    endrule

    rule deallocate_storage if (token_request_fifo.first matches tagged Tag_Deallocate_Storage { .ptr });
        free[ptr] <= True;
        token_request_fifo.deq;
        read_ptr <= 0; // This is kind of redundant but i thought it would not hurt.
    endrule

    method Action put_data(ChannelMessage msg);
        input_fifo.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get_token();
        let msg = token_output_fifo.first;
        token_output_fifo.deq;
        return msg;
    endmethod

    method Action request_token(ChannelMessage msg);
        token_request_fifo.enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get_data();
        let msg = output_fifo.first;
        output_fifo.deq;
        return msg;
    endmethod

    interface Operation_IFC operation;
        method Action put(Int#(32) i, ChannelMessage msg); // i = 0 for data, 1 for token
            if (i == 0) begin
                input_fifo.enq(msg);
            end else begin
                token_request_fifo.enq(msg);
            end
        endmethod

        method ActionValue#(ChannelMessage) get(Int#(32) i); // i = 0 for token, 1 for data
            ChannelMessage msg;
            if (i == 0) begin
                token_output_fifo.deq;
                msg = token_output_fifo.first;
            end else begin
                output_fifo.deq;
                msg = output_fifo.first;
            end
            return msg;
        endmethod
    endinterface
endmodule

module mkBufferize(Empty);
    Bufferize#(4) dut <- mkSimpleBufferize(1, 4);
    let rpt <- mkRepeatStatic(10);
    let drained <- mkReg(0);

    let state <- mkReg(0);

    rule push if (state == 0);
        let data = tagged Tag_Data (tuple2(Tag_Tile (0), 1));
        dut.put_data(data);
        state <= state + 1;
    endrule

    rule token_output_to_repeat_input;
        let data <- dut.get_token();
        rpt.put(0, data);
    endrule

    rule repeat_output_to_bufferize_input;
        let data <- rpt.get(0);
        $display("Repeat output: ", fshow(data));
        dut.request_token(data);
    endrule

    rule drain_result;
        let data <- dut.get_data();
        $display("data: ", fshow(data), "end.");
        drained <= drained + 1;
        if (drained == 9) begin
            $finish(0);
        end
    endrule

endmodule