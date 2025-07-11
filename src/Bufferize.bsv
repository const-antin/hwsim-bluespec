import Vector::*;
import FIFO::*;
import FIFOF::*;
import Types::*;
import Operation::*;

typedef 2 NUM_ENTRIES;
typedef TMul#(TILE_SIZE, TILE_SIZE) SIZE_PER_ENTRY;

interface Bufferize;
    method Action put_data(ChannelMessage msg);
    method ActionValue#(ChannelMessage) get_token();
    method Action request_token(ChannelMessage msg);
    method ActionValue#(ChannelMessage) get_data();
endinterface

module mkSimpleBufferize#(Int#(32) rank) (Bufferize);
    FIFOF#(ChannelMessage) input_fifo <- mkFIFOF;
    FIFOF#(ChannelMessage) output_fifo <- mkFIFOF;
    FIFOF#(ChannelMessage) token_request_fifo <- mkFIFOF;    
    FIFOF#(ChannelMessage) token_output_fifo <- mkFIFOF;

    FIFOF#(Tuple2#(Ref, StopToken)) token_output_stage <- mkFIFOF;
    Reg#(Bool) token_output_stage_state <- mkReg(False);

    Reg#(Vector#(NUM_ENTRIES, Vector#(SIZE_PER_ENTRY, Maybe#(Tuple2#(Data, StopToken))))) buffer <- mkReg(replicate(replicate(tagged Invalid)));
    Reg#(Vector#(NUM_ENTRIES, Bool)) free <- mkReg(replicate(True));

    Reg#(Ref) write_ptr <- mkReg(0);
    Reg#(Int#(32)) write_subptr <- mkReg(0);
    
    Reg#(Int#(32)) read_ptr <- mkReg(0);

    (* descending_urgency = "deallocate_storage, store" *)
    rule store if (free[write_ptr] == True &&& input_fifo.first matches tagged Tag_Data { .data, .st });
        input_fifo.deq;
        buffer[write_ptr][write_subptr] <= tagged Valid (tuple2(data, st));
        if (st >= rank) begin 
            write_ptr <= (write_ptr + 1) % fromInteger(valueOf(NUM_ENTRIES));
            write_subptr <= 0;
            token_output_stage.enq(tuple2(write_ptr, st - rank));
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

            let el = buffer[ptr][read_ptr];
            if ((read_ptr < fromInteger(valueOf(NUM_ENTRIES))) &&& isValid(el) )
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
endmodule

module mkBufferize(Empty);
    let dut <- mkSimpleBufferize(1);
    let rpt <- mkRepeatStatic(10);

    let state <- mkReg(0);

    rule push if (state == 0);
        let data = tagged Tag_Data (tuple2(Tag_Tile (replicate(replicate(state))), 1));
        dut.put_data(data);
        state <= state + 1;
    endrule

    rule token_output_to_repeat_input;
        let data <- dut.get_token();
        rpt.put(0, data);
    endrule

    rule repeat_output_to_bufferize_input;
        let data <- rpt.get(0);
        dut.request_token(data);
    endrule

    rule drain_result;
        let data <- dut.get_data();
        $finish(0);
    endrule

endmodule