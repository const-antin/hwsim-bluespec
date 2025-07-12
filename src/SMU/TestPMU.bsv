package TestPMU;

import PMU::*;
import Types::*;
import Vector::*;
import FIFO::*;
import Parameters::*;

typedef 8 NUM_TEST_VALUES;

// Function to print a tile matrix
function Action printTile(TaggedTile tile);
    return action
        for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1) begin
            $write("  ");
            for (Integer j = 0; j < valueOf(TILE_SIZE); j = j + 1) begin
                $write("%0d ", tile.t[i][j]);
            end
            $write("\n");
        end
    endaction;
endfunction

(* synthesize *)
module mkTestPMU();
    // Create the four FIFOs that connect to the PMU
    FIFO#(TaggedTile) data_in <- mkFIFO;
    FIFO#(Int#(32)) token_out <- mkFIFO;
    FIFO#(Int#(32)) token_in <- mkFIFO;
    FIFO#(TaggedTile) data_out <- mkFIFO;
    
    PMU_IFC pmu <- mkPMU(data_in, token_out, token_in, data_out);

    // === Dynamically create NUM_TEST_VALUES test matrices ===
    Vector#(NUM_TEST_VALUES, TaggedTile) testValues;
    for (Integer i = 0; i < valueOf(NUM_TEST_VALUES); i = i + 1) begin
        Vector#(TILE_SIZE, Vector#(TILE_SIZE, Scalar)) mat = replicate(replicate(0));
        mat[0][0] = fromInteger(4*i + 0);
        mat[0][1] = fromInteger(4*i + 1);
        mat[1][0] = fromInteger(4*i + 2);
        mat[1][1] = fromInteger(4*i + 3);
        testValues[i] = TaggedTile { t: mat, st: fromInteger(100 + i) };
    end

    // === State tracking ===
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 1)))) putIndex <- mkReg(0);
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 1)))) getIndex <- mkReg(0);
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 1)))) valIndex <- mkReg(0);
    Vector#(NUM_TEST_VALUES, Reg#(Int#(32))) tokens <- replicateM(mkReg(0));
    Reg#(Bool) testDone <- mkReg(False);

    // === Put values ===
    rule putValue(!testDone && putIndex < fromInteger(valueOf(NUM_TEST_VALUES)));
        data_in.enq(testValues[putIndex]);
        $display("Test: Putting value");
        printTile(testValues[putIndex]);
        putIndex <= putIndex + 1;
    endrule

    // === Handle token output ===
    rule handleToken(!testDone);
        let token = token_out.first;
        token_out.deq;
        tokens[getIndex] <= token;
        $display("Test: Got token %d for value", token);
        printTile(testValues[getIndex]);
        getIndex <= getIndex + 1;

        token_in.enq(token);
        $display("Test: Requesting value for token %d", token);
    endrule

    // === Handle returned value ===
    rule handleValue(!testDone);
        let value = data_out.first;
        data_out.deq;

        let idx = valIndex;
        let token = tokens[idx];
        let expected = testValues[idx];
        valIndex <= valIndex + 1;

        if (value == expected) begin
            $display("Test PASSED: Token %d", token);
        end else begin
            $display("FAILED: Returned [st = %0d]:", value.st);
            printTile(value);
            $display("Expected [st = %0d]:", expected.st);
            printTile(expected);
        end

        if (valIndex + 1 == fromInteger(valueOf(NUM_TEST_VALUES))) begin
            testDone <= True;
            $display("All tests completed");
            $finish(0);
        end
    endrule

endmodule

endpackage
