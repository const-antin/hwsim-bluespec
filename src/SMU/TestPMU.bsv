package TestPMU;

import PMU::*;
import Types::*;
import Vector::*;
import FIFO::*;
import Parameters::*;

(* synthesize *)
module mkTestPMU();
    // Create the four FIFOs that connect to the PMU
    FIFO#(TaggedTile) data_in <- mkFIFO;
    FIFO#(Int#(32)) token_out <- mkFIFO;
    FIFO#(Int#(32)) token_in <- mkFIFO;
    FIFO#(TaggedTile) data_out <- mkFIFO;
    
    PMU_IFC pmu <- mkPMU(data_in, token_out, token_in, data_out);
    
    Vector#(4, TaggedTile) testValues;
    Vector#(TILE_SIZE, Vector#(TILE_SIZE, Scalar)) mat1 = replicate(replicate(0));
    Vector#(TILE_SIZE, Vector#(TILE_SIZE, Scalar)) mat2 = replicate(replicate(0));
    Vector#(TILE_SIZE, Vector#(TILE_SIZE, Scalar)) mat3 = replicate(replicate(0));
    Vector#(TILE_SIZE, Vector#(TILE_SIZE, Scalar)) mat4 = replicate(replicate(0));

    mat1[0][0] = 1; mat1[0][1] = 2;
    mat1[1][0] = 3; mat1[1][1] = 4;
    
    mat2[0][0] = 5; mat2[0][1] = 6;
    mat2[1][0] = 7; mat2[1][1] = 8;
    
    mat3[0][0] = 9; mat3[0][1] = 10;
    mat3[1][0] = 11; mat3[1][1] = 12;
    
    mat4[0][0] = 13; mat4[0][1] = 14;
    mat4[1][0] = 15; mat4[1][1] = 16;
                   
    testValues[0] = TaggedTile { t: mat1, st: 100 };
    testValues[1] = TaggedTile { t: mat2, st: 101 };
    testValues[2] = TaggedTile { t: mat3, st: 102 };
    testValues[3] = TaggedTile { t: mat4, st: 103 };
    
    Reg#(Bit#(3)) putIndex <- mkReg(0);
    Reg#(Bit#(3)) getIndex <- mkReg(0);
    Reg#(Bit#(3)) valIndex <- mkReg(0);
    Vector#(4, Reg#(Int#(32))) tokens <- replicateM(mkReg(0));
    Reg#(Bool) testDone <- mkReg(False);
    
    // Put values one at a time
    rule putValue(!testDone && putIndex < 4);
        data_in.enq(testValues[putIndex]);
        $display("Test: Putting value %d", testValues[putIndex]);
        putIndex <= putIndex + 1;
    endrule
    
    // Handle tokens whenever they appear
    rule handleToken(!testDone);
        let token = token_out.first;
        token_out.deq;
        tokens[getIndex] <= token;
        $display("Test: Got token %d for value %d", token, testValues[getIndex]);
        getIndex <= getIndex + 1;
        
        // Request the value back immediately
        token_in.enq(token);
        $display("Test: Requesting value for token %d", token);
    endrule
    
    // Handle returned values whenever they appear
    rule handleValue(!testDone);
        let value = data_out.first;
        data_out.deq;
        // Find which token this was for (we can do this because we know the order)
        let idx = valIndex;
        let token = tokens[idx];
        let expected = testValues[idx];
        valIndex <= valIndex + 1;
        
        if (value == expected) begin
            $display("Test PASSED: Token %d -> Value %d (expected %d)", 
                    token, value, expected);
        end else begin
            $display("Test FAILED: Token %d -> Value %d (expected %d)", 
                    token, value, expected);
        end
        
        if (putIndex == 4 && idx == 3) begin
            testDone <= True;
            $display("All tests completed");
            $finish(0);
        end
    endrule

endmodule

endpackage