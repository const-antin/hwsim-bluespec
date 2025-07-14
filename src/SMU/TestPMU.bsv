package TestPMU;

import PMU::*;
import Types::*;
import Vector::*;
import FIFO::*;
import Parameters::*;

typedef 7 NUM_TEST_VALUES;
typedef 1 RANK;

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
        $write("  st: %0d\n", tile.st);
    endaction;
endfunction

(* synthesize *)
module mkTestPMU();
    // Create the four FIFOs that connect to the PMU
    FIFO#(ChannelMessage) data_in <- mkFIFO;
    FIFO#(ChannelMessage) token_out <- mkFIFO;
    FIFO#(ChannelMessage) token_in <- mkFIFO;
    FIFO#(ChannelMessage) data_out <- mkFIFO;
    
    PMU_IFC pmu <- mkPMU(data_in, token_out, token_in, data_out, fromInteger(valueOf(RANK)));

    // === Dynamically create NUM_TEST_VALUES test matrices ===
    Vector#(NUM_TEST_VALUES, TaggedTile) testValues;
    for (Integer i = 0; i < valueOf(NUM_TEST_VALUES); i = i + 1) begin
        Vector#(TILE_SIZE, Vector#(TILE_SIZE, Scalar)) mat = replicate(replicate(0));
        mat[0][0] = fromInteger(4*i + 0);
        mat[0][1] = fromInteger(4*i + 1);
        mat[1][0] = fromInteger(4*i + 2);
        mat[1][1] = fromInteger(4*i + 3);
        testValues[i] = TaggedTile { t: mat, st: fromInteger(0) };                
    end
    testValues[2].st = fromInteger(1);
    testValues[6].st = fromInteger(2);

    // === State tracking ===
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) putIndex <- mkReg(0);
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) getIndex <- mkReg(0);
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) valIndex <- mkReg(0);
    Vector#(NUM_TEST_VALUES, Reg#(Int#(32))) tokens <- replicateM(mkReg(0));

    // === Put values ===
    rule driveInput;
        if (putIndex < fromInteger(valueOf(NUM_TEST_VALUES))) begin 
            data_in.enq(tagged Tag_Data tuple2(tagged Tag_Tile testValues[putIndex].t, testValues[putIndex].st));
            // $display("Test: Putting value");
            // printTile(testValues[putIndex]);
            putIndex <= putIndex + 1;
        end else if (putIndex == fromInteger(valueOf(NUM_TEST_VALUES))) begin
            data_in.enq(tagged Tag_EndToken 0);
            putIndex <= putIndex + 1;
            // $display("Test: Putting end token");
        end
    endrule

    // === Handle token output ===
    rule handleToken;
        let token = token_out.first;
        token_out.deq;
        case (token) matches
            tagged Tag_Data {.d, .st}: begin
                case (d) matches
                    tagged Tag_Scalar .s: begin
                        tokens[getIndex] <= s;
                        $display("Test: Got token %d %d", s, st);
                        getIndex <= getIndex + 1;
                        token_in.enq(tagged Tag_Data tuple2(tagged Tag_Scalar s, st));
                    end
                    default: begin
                        $display("Expected scalar token, got something else");
                        $finish(0);
                    end
                endcase
            end
            tagged Tag_EndToken .et: begin
                $display("Test: End token received in token out");
                token_in.enq(tagged Tag_EndToken 0);
            end
            default: begin
                $display("Expected Tag_Data in token_out");
                $finish(0);
            end
        endcase
    endrule

    // === Handle returned value ===
    rule handleValue;
        let value = data_out.first;
        data_out.deq;

        case (value) matches
            tagged Tag_Data {.d, .st}: begin
                case (d) matches
                    tagged Tag_Tile .t: begin
                        let expected = testValues[valIndex];
                        valIndex <= valIndex + 1;

                        if (TaggedTile { t: t, st: st } == expected) begin
                            $display("PASSED:");
                            printTile(TaggedTile { t: t, st: st });
                            $display("Expected [st = %0d]:", expected.st);
                            printTile(expected);
                        end else begin
                            $display("FAILED:");
                            printTile(TaggedTile { t: t, st: st });
                            $display("Expected [st = %0d]:", expected.st);
                            printTile(expected);
                            // $finish(0); // Exits on failure
                        end
                    end
                    default: begin
                        $display("Expected tile, got something else");
                        $finish(0);
                    end
                endcase
            end
            tagged Tag_EndToken .et: begin
                $display("Test: End token received");
                $display("All tests completed");
                $finish(0);
            end
            default: begin
                $display("Expected Tag_Data in data_out");
                $finish(0);
            end
        endcase
    endrule

endmodule

endpackage
