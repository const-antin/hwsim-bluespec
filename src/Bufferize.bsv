import Vector::*;
import FIFO::*;
import FIFOF::*;
import Types::*;

typedef 4 NUM_ENTRIES;
typedef 2 SIZE_PER_ENTRY;

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
    (* preempts = "store, store_debug" *)
    rule store if (free[write_ptr] == True &&& input_fifo.first matches tagged Tag_Data { .data, .st });
        // $display("storing data: %s", fshow(data));
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

    rule store_debug;
    /*
        $display("buffer: %s", fshow(buffer));
        $display("free: %s", fshow(free[write_ptr]));
        $display("input_fifo not full: %s", fshow(input_fifo.notFull));
        $display("input fifo first: %s", fshow(input_fifo.first));
        $display("input_fifo not empty: %s", fshow(input_fifo.notEmpty));
        $display("output_fifo: %s", fshow(output_fifo.notFull));
        $display("token_request_fifo: %s", fshow(token_request_fifo.notFull));
        $display("token_output_fifo: %s", fshow(token_output_fifo.notFull));
        $display("token_output_stage: %s", fshow(token_output_stage.notFull));
        $display("write_ptr: %d", write_ptr);
        $display("write_subptr: %d", write_subptr);
        $display("read_ptr: %d", read_ptr);
        */
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
        // $display("deallocating storage: %d", ptr);
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

    rule push;
        let data = tagged Tag_Data (tuple2(Tag_Tile (replicate(replicate(1))), 1));
        dut.put_data(data);
    endrule

    rule loop_data;
        let data <- dut.get_token();
        dut.request_token(data);
    endrule

    rule drain_result;
        let data <- dut.get_data();
        $display("data: %s", fshow(data));
        // $finish(0);
    endrule

endmodule