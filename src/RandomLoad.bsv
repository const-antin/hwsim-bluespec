import Parameters::*;
import Types::*;
import Operation::*;
import FShow::*;
import List::*;
import Randomizable::*;

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
            // let payload = 0;
            data = Tag_Data(tuple2(Tag_Tile(payload), st));
        end
        return data;
    endmethod

    method Action put(Int#(32) index, ChannelMessage tile);
        $display("Called put on a RandomOffChipLoad, which cannot store data.");
        $finish();
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