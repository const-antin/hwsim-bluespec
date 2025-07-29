package TestPMU;

import PMU::*;
import Types::*;
import Vector::*;
import FIFO::*;
import Parameters::*;
import RegFile::*;
import ConfigReg::*;        // Added for the new test
import Operation::*;        // Added for the new test
// import YourRepeatPackage::*;  // Uncomment and specify the correct package for mkRepeatStatic

// Existing test parameters
typedef 23 NUM_TEST_VALUES;
typedef 1 RANK;

// New test parameters  
typedef 1 NUM_ENTRIES;
typedef 4 ENTRY_SIZE;

// Function to print a tile matrix
// function Action printTile(TaggedTile tile);
//     return action
//         for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1) begin
//             $write("  ");
//             for (Integer j = 0; j < valueOf(TILE_SIZE); j = j + 1) begin
//                 $write("%0d ", unpack(tile.t)[i*valueOf(TILE_SIZE) + j]);
//             end
//             $write("\n");
//         end
//         $write("  st: %0d\n", tile.st);
//     endaction;
// endfunction

// ============================================================================
// Original comprehensive test module
// ============================================================================
(* synthesize *)
module mkTestPMU();
    PMU_IFC pmu <- mkPMU(fromInteger(valueOf(RANK)));

    function TaggedTile testValues(Bit#(TLog#(TAdd#(TestPMU::NUM_TEST_VALUES, 2))) i);
        Vector#(TILE_SIZE, Vector#(TILE_SIZE, Scalar)) mat = replicate(replicate(0));
        StopToken token = 0;
        if (i == fromInteger(valueOf(NUM_TEST_VALUES) / 2 - 1)) begin
            token = 1;
        end
        if (i == fromInteger(valueOf(NUM_TEST_VALUES) - 1)) begin
            token = 2;
        end
        
        let cur = unpack(extend(i));
        mat[0][0] = 4*cur + 0;
        mat[0][1] = 4*cur + 1;
        mat[1][0] = 4*cur + 2;
        mat[1][1] = 4*cur + 3;
        return TaggedTile { t: pack(mat), st: token };
    endfunction

    // === State tracking ===
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) putIndex <- mkReg(0);
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) getIndex <- mkReg(0);
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) valIndex <- mkReg(0);
    // RegFile#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2))), Tuple2#(Bit#(32), Bool)) tokens <- mkRegFileFull();
    // Vector#(NUM_TEST_VALUES, Reg#(Tuple2#(Bit#(32), Bool))) tokens <- replicateM(mkReg(tuple2(0, False)));

    // Reg#(Bool) started <- mkReg(True);

    // rule wait_until_ready (!started);
    //     if (pmu.ready()) begin
    //         $display("[TESTBENCH] PMU is ready.");
    //         started <= True;
    //     end
    // endrule

    // === Put values ===
    rule driveInput;
        if (putIndex < fromInteger(valueOf(NUM_TEST_VALUES))) begin 
            pmu.put_data(tagged Tag_Data tuple2(tagged Tag_Tile testValues(putIndex).t, testValues(putIndex).st));
            // $display("Test: Putting value");
            // printTile(testValues[putIndex]);
            putIndex <= putIndex + 1;
        end else if (putIndex == fromInteger(valueOf(NUM_TEST_VALUES))) begin
            pmu.put_data(tagged Tag_EndToken 0);
            putIndex <= putIndex + 1;
            // $display("Test: Putting end token");
        end
    endrule

    // === Handle token output ===
    rule handleToken;
        let token <- pmu.get_token();
        case (token) matches
            tagged Tag_Data {.d, .st}: begin
                case (d) matches
                    tagged Tag_Ref {.r, .deallocate}: begin
                        // tokens.upd(getIndex, tuple2(r, deallocate));
                        $display("Test: Got token %d %d %d", r, deallocate, st);
                        getIndex <= getIndex + 1;
                        pmu.put_token(tagged Tag_Data tuple2(tagged Tag_Ref tuple2(r, True), st));
                    end
                    default: begin
                        $display("Expected scalar token, got something else");
                        $finish(0);
                    end
                endcase
            end
            tagged Tag_EndToken .et: begin
                $display("Test: End token received in token out");
                pmu.put_token(tagged Tag_EndToken 0);
            end
            default: begin
                $display("Expected Tag_Data in token_out");
                $finish(0);
            end
        endcase
    endrule

    // === Handle returned value ===
    rule handleValue;
        let value <- pmu.get_data();

        case (value) matches
            tagged Tag_Data {.d, .st}: begin
                case (d) matches
                    tagged Tag_Tile .t: begin
                        let expected = testValues(valIndex);
                        valIndex <= valIndex + 1;

                        if (TaggedTile { t: t, st: st } == expected) begin
                            $display("PASSED:");
                            // printTile(TaggedTile { t: t, st: st });
                            $display("Expected [st = %0d]:", expected.st);
                            $display("Got [st = %0d]:", st);
                            // printTile(expected);
                        end else begin
                            $display("FAILED:");
                            // printTile(TaggedTile { t: t, st: st });
                            $display("Expected [st = %0d]:", expected.st);
                            $display("Got [st = %0d]:", st);
                            // printTile(expected);
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
                $display("All tests completed at cycle %d", pmu.get_cycle_count());
                $finish(0);
            end
            default: begin
                $display("Expected Tag_Data in data_out");
                $finish(0);
            end
        endcase
    endrule

endmodule

// ============================================================================
// Stop token test with repeat module
// ============================================================================
(* synthesize *)
module mkTestPMUStopToken(Empty);
    let rank = 3;
    PMU_IFC dut <- mkPMU(rank);
    let rpt <- mkRepeatStatic(2);  
    let drained <- mkReg(0);
    
    Reg#(UInt#(32)) state <- mkReg(1);

    rule push if (state % fromInteger(valueOf(ENTRY_SIZE)) != 0 && state < 10 * fromInteger(valueOf(ENTRY_SIZE)));
        let data = tagged Tag_Data (tuple2(tagged Tag_Tile (0), 0));
        dut.put_data(data);
        state <= state + 1;
    endrule

    rule push_2 if (state % fromInteger(valueOf(ENTRY_SIZE)) == 0);
        let data = tagged Tag_Data (tuple2(tagged Tag_Tile (1), rank));
        dut.put_data(data);
        state <= state + 1;
        $display("pushed everything.");
    endrule

    rule token_output_to_repeat_input;
        let data <- dut.get_token();
        // data = tagged Tag_Data (tuple2(tpl_1(data.Tag_Data), tpl_2(data.Tag_Data) + 1));
        $display("Forwarded to repeat.");
        rpt.put(0, data);
    endrule

    rule repeat_output_to_pmu_input;
        let data <- rpt.get(0);
        // $display("Repeat output: ", fshow(data));
        dut.put_token(data);
    endrule

    rule drain_result;
        let data <- dut.get_data();
        $display("data: ", fshow(data), "end.");
        drained <= drained + 1;
        // if (drained == 9) begin
        //     $finish(0);
        // end
    endrule

endmodule

// ============================================================================
// Helper modules (you may need to define mkRepeatStatic if its not available)
// ============================================================================

// Uncomment and modify this if you dont have mkRepeatStatic available elsewhere
/*
interface RepeatStatic_IFC;
    method Action put(Int#(32) i, ChannelMessage msg);
    method ActionValue#(ChannelMessage) get(Int#(32) i);
endinterface

module mkRepeatStatic#(Integer delay)(RepeatStatic_IFC);
    FIFO#(ChannelMessage) fifo <- mkSizedFIFO(delay + 1);
    
    method Action put(Int#(32) i, ChannelMessage msg);
        fifo.enq(msg);
    endmethod
    
    method ActionValue#(ChannelMessage) get(Int#(32) i);
        fifo.deq();
        return fifo.first();
    endmethod
endmodule
*/

endpackage