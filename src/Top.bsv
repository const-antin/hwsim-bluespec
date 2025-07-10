package Top;

import FloatingPoint::*;
import Vector::*;
import FShow::*;
import Stage::*;
import Types::*;
import Interconnect::*;

// Top.bsv
// A simple counter program in Bluespec SystemVerilog

interface Tmp_IFC;
    method Action put(Integer i, Int#(32) value);
    method ActionValue#(Int#(32)) get(Integer i);
endinterface

module mkTmp(Tmp_IFC);
    Vector#(5, Reg#(Int#(32))) values <- replicateM(mkReg(0));

    method Action put(Integer i, Int#(32) value);
        values[i] <= value;
    endmethod

    method ActionValue#(Int#(32)) get(Integer i);
        return values[i];
    endmethod
endmodule

// Top module that runs the test
module mkTop(Empty);
    Tmp_IFC tmp <- mkTmp();

    Reg#(Int#(32)) state <- mkReg(0);

    rule put if (state == 0); 
        tmp.put(0, 1);
        tmp.put(1, 2);
        state <= 1;
    endrule

    rule get if (state == 1);
        let value <- tmp.get(0);
        let value2 <- tmp.get(1);
        $display("value: %d", value);
        $display("value2: %d", value2);
        state <= 2;
    endrule
endmodule

endpackage 