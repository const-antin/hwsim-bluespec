import Parameters::*;
import Types::*;
import Operation::*;
import FShow::*;
import List::*;
import FIFO::*;
import Types::*;
import Randomizable::*;
import StmtFSM::*;

module mkRandomOffChipLoad#(List#(Int#(32)) shape) (Operation_IFC);
    let randomizer <- mkGenericRandomizer;
    Reg#(Int#(32)) ctr <- mkReg(1);
    Reg#(Bool) init <- mkReg(False);
    Reg#(Bool) sent_end <- mkReg(False);

    function mul(x, y) = x * y;
    let size = sscanl(mul, 1, shape);


    rule go if (!init);
        randomizer.cntrl.init();
        init <= True;
    endrule

    method ActionValue#(ChannelMessage) get(Int#(32) index) if (init &&& (ctr <= last(size) || !sent_end));
        ChannelMessage data;
        if (ctr > last(size)) begin
            data = Tag_EndToken;
            sent_end <= True;
        end else begin
            $display("Index: %d", ctr);
            $display("Size: %s", fshow(size));
            StopToken st = 0;
            for (Int#(32) i = 0; i < fromInteger(length(shape)); i = i + 1) begin
                if (ctr % size[i] == 0) begin
                    st = st + 1;
                end
            end
            ctr <= ctr + 1;
            let payload <- randomizer.next();
            data = Tag_Data(tuple2(Tag_Tile(payload), st));
        end
        return data;
    endmethod

    method Action put(Int#(32) index, ChannelMessage tile);
        $display("Called put on a RandomOffChipLoad, which cannot store data.");
        $finish();
    endmethod 
endmodule 

typedef union tagged {
    void Tag_DLS_Uninitialized;
    void Tag_DLS_Waiting;
    StopToken Tag_DLS_Running;
    void Tag_DLS_Finished;
    void Tag_DLS_Finished_And_Sent;
} DynamicLoadState deriving (Bits, Eq, FShow);

module mkDynamicRandomLoad#(List#(Int#(32)) shape) (Operation_IFC);
    FIFO#(ChannelMessage) input_fifo <- mkFIFO;
    FIFO#(ChannelMessage) output_fifo <- mkFIFO;

    let randomizer <- mkGenericRandomizer;
    Reg#(Int#(32)) ctr <- mkReg(1);
    Reg#(DynamicLoadState) state <- mkReg(Tag_DLS_Uninitialized);

    function mul(x, y) = x * y;
    let size = sscanl(mul, 1, shape);

    rule disp_state;
        // $display("Current state: %s", fshow(state));
    endrule

    rule init if (state matches tagged Tag_DLS_Uninitialized);
        randomizer.cntrl.init();
        state <= Tag_DLS_Waiting;
    endrule

    rule kickoff if (state matches tagged Tag_DLS_Waiting);
        if (input_fifo.first matches tagged Tag_EndToken) begin
            state <= Tag_DLS_Finished;
        end else begin
            input_fifo.deq;
            ctr <= 1;
            state <= Tag_DLS_Running (tpl_2(input_fifo.first.Tag_Data));
        end
    endrule

    rule run if (state matches tagged Tag_DLS_Running .input_st);
        ctr <= ctr + 1;
        if (ctr > last(size)) begin
            state <= Tag_DLS_Waiting;
        end else begin
            StopToken st = 0;
            for (Int#(32) i = 0; i < fromInteger(length(shape)); i = i + 1) begin
                if (ctr % size[i] == 0) begin
                    st = st + 1;
                end
            end
            if (ctr == last(size)) begin // Take rank of input into account.
                st = st + input_st;
            end
            let payload <- randomizer.next();
            let data = Tag_Data(tuple2(Tag_Tile(payload), st));
            output_fifo.enq(data);
        end
    endrule

    rule finish if (state == Tag_DLS_Finished);
        output_fifo.enq(tagged Tag_EndToken);
        state <= Tag_DLS_Finished_And_Sent;
    endrule

    method ActionValue#(ChannelMessage) get(Int#(32) index);
        output_fifo.deq;
        return output_fifo.first;
    endmethod

    method Action put(Int#(32) index, ChannelMessage tile);
        input_fifo.enq(tile);
    endmethod 
endmodule


module mkRandomSelectGen#(Int#(32) num_experts) (Operation_IFC);
    let randomizer <- mkConstrainedRandomizer(0, (2 << num_experts) - 1);
    Reg#(Bool) init <- mkReg(False);

    rule go if (!init);
        randomizer.cntrl.init();
    endrule

    method ActionValue#(ChannelMessage) get(Int#(32) index);
        Selector next <- randomizer.next();
        return tagged Tag_Data tuple2(tagged Tag_Selector (next), 0);
    endmethod 

    method Action put(Int#(32) index, ChannelMessage tile);
        $display("Put should never be called on random select gen!");
        $finish(-1);
    endmethod

endmodule

module mkRandomOffChipLoadTest (Empty);
    List#(Int#(32)) l = Cons(4, Cons(2, Cons(3, Nil)));
    let offchipload <- mkRandomOffChipLoad(l);

    rule drain;
        let t <- offchipload.get(0);
        $display("Received tile: %s\n", fshow(tpl_2(t.Tag_Data)));
    endrule
endmodule

module mkDynamicRandomLoadTest (Empty);
    List#(Int#(32)) l = Cons(1, Cons(2, Cons(1, Nil)));
    let dload <- mkDynamicRandomLoad(l);
    
    Reg#(Int#(32)) i <- mkReg(0);

    let fsm <- mkAutoFSM (
        par
            seq 
                action
                    dload.put(0, tagged Tag_Data tuple2(Tag_Ref (unpack(0)), 0));
                    $display("Put tile with ref 0");
                endaction
                action
                    dload.put(0, tagged Tag_Data tuple2(Tag_Ref (unpack(1)), 1));
                    $display("Put tile with ref 1");
                endaction
                action
                    dload.put(0, tagged Tag_EndToken);
                    $display("Put end token");
                endaction
            endseq
            seq
                action
                    let t <- dload.get(0);
                    if (t matches tagged Tag_Data .td &&& tpl_2(td) == 1) begin
                        // nothing 
                    end else begin
                        $display("Error: Expected tile with ref 1, got %s", fshow(t));
                        $finish(-1);
                    end 
                endaction
                action
                    let t <- dload.get(0);
                    if (t matches tagged Tag_Data .td &&& tpl_2(td) == 3) begin
                        // nothing 
                    end else begin
                        $display("Error: Expected tile with ref 3, got %s", fshow(t));
                        $finish(-1);
                    end 
                endaction
                action
                    let t <- dload.get(0);
                    if (t matches tagged Tag_Data .td &&& tpl_2(td) == 1) begin
                        // nothing 
                    end else begin
                        $display("Error: Expected tile with ref 1, got %s", fshow(t));
                        $finish(-1);
                    end 
                endaction
                action
                    let t <- dload.get(0);
                    if (t matches tagged Tag_Data .td &&& tpl_2(td) == 4) begin
                        // nothing 
                    end else begin
                        $display("Error: Expected tile with ref 4, got %s", fshow(t));
                        $finish(-1);
                    end 
                endaction
                action
                    let t <- dload.get(0);
                    if (t matches tagged Tag_EndToken) begin
                        $display("Received end token");
                    end else begin
                        $display("Error: Expected end token, got %s", fshow(t));
                        $finish(-1);
                    end
                endaction
                
            endseq 
        endpar
    );
endmodule