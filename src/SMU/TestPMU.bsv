package TestPMU;

import PMU::*;
import Types::*;
import Vector::*;
import FIFOF::*;
import Parameters::*;
import RegFile::*;
import ConfigReg::*;        // Added for the new test
import Operation::*;        // Added for the new test
// import YourRepeatPackage::*;  // Uncomment and specify the correct package for mkRepeatStatic

// Existing test parameters
typedef 40 NUM_TEST_VALUES;
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
// (* synthesize *)
// module mkTestPMU();
//     Vector#(10, Vector#(4, FIFOF#(MessageType))) dummy_fifos <- replicateM(replicateM(mkFIFOF));
//     PMU_IFC pmu <- mkPMU(fromInteger(valueOf(RANK)), Coords { x: 0, y: 0 }, dummy_fifos[0], dummy_fifos[1], dummy_fifos[2], dummy_fifos[3], dummy_fifos[4], dummy_fifos[5], dummy_fifos[6], dummy_fifos[7], dummy_fifos[8], dummy_fifos[9]);

//     function TaggedTile testValues(Bit#(TLog#(TAdd#(TestPMU::NUM_TEST_VALUES, 2))) i);
//         Vector#(TILE_SIZE, Vector#(TILE_SIZE, Scalar)) mat = replicate(replicate(0));
//         StopToken token = 0;
//         if (i == fromInteger(valueOf(NUM_TEST_VALUES) / 2 - 1)) begin
//             token = 1;
//         end
//         if (i == fromInteger(valueOf(NUM_TEST_VALUES) - 1)) begin
//             token = 2;
//         end
        
//         let cur = unpack(extend(i));
//         mat[0][0] = 4*cur + 0;
//         mat[0][1] = 4*cur + 1;
//         mat[1][0] = 4*cur + 2;
//         mat[1][1] = 4*cur + 3;
//         return TaggedTile { t: pack(mat), st: token };
//     endfunction

//     // === State tracking ===
//     Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) putIndex <- mkReg(0);
//     Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) getIndex <- mkReg(0);
//     Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) valIndex <- mkReg(0);
//     // RegFile#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2))), Tuple2#(Bit#(32), Bool)) tokens <- mkRegFileFull();
//     // Vector#(NUM_TEST_VALUES, Reg#(Tuple2#(Bit#(32), Bool))) tokens <- replicateM(mkReg(tuple2(0, False)));

//     // Reg#(Bool) started <- mkReg(True);

//     // rule wait_until_ready (!started);
//     //     if (pmu.ready()) begin
//     //         $display("[TESTBENCH] PMU is ready.");
//     //         started <= True;
//     //     end
//     // endrule

//     // === Put values ===
//     rule driveInput;
//         if (putIndex < fromInteger(valueOf(NUM_TEST_VALUES))) begin 
//             pmu.put_data(tagged Tag_Data tuple2(tagged Tag_Tile testValues(putIndex).t, testValues(putIndex).st));
//             // $display("Test: Putting value");
//             // printTile(testValues[putIndex]);
//             putIndex <= putIndex + 1;
//         end else if (putIndex == fromInteger(valueOf(NUM_TEST_VALUES))) begin
//             pmu.put_data(tagged Tag_EndToken 0);
//             putIndex <= putIndex + 1;
//             // $display("Test: Putting end token");
//         end
//     endrule

//     // === Handle token output ===
//     rule handleToken;
//         let token <- pmu.get_token();
//         case (token) matches
//             tagged Tag_Data {.d, .st}: begin
//                 case (d) matches
//                     tagged Tag_Ref {.r, .deallocate}: begin
//                         // tokens.upd(getIndex, tuple2(r, deallocate));
//                         $display("Test: Got token %d %d %d", r, deallocate, st);
//                         getIndex <= getIndex + 1;
//                         pmu.put_token(tagged Tag_Data tuple2(tagged Tag_Ref tuple2(r, True), st));
//                     end
//                     default: begin
//                         $display("Expected scalar token, got something else");
//                         $finish(0);
//                     end
//                 endcase
//             end
//             tagged Tag_EndToken .et: begin
//                 $display("Test: End token received in token out");
//                 pmu.put_token(tagged Tag_EndToken 0);
//             end
//             default: begin
//                 $display("Expected Tag_Data in token_out");
//                 $finish(0);
//             end
//         endcase
//     endrule

//     // === Handle returned value ===
//     rule handleValue;
//         let value <- pmu.get_data();

//         case (value) matches
//             tagged Tag_Data {.d, .st}: begin
//                 case (d) matches
//                     tagged Tag_Tile .t: begin
//                         let expected = testValues(valIndex);
//                         valIndex <= valIndex + 1;

//                         if (TaggedTile { t: t, st: st } == expected) begin
//                             $display("PASSED:");
//                             // printTile(TaggedTile { t: t, st: st });
//                             $display("Expected [st = %0d]:", expected.st);
//                             $display("Got [st = %0d]:", st);
//                             // printTile(expected);
//                         end else begin
//                             $display("FAILED:");
//                             // printTile(TaggedTile { t: t, st: st });
//                             $display("Expected [st = %0d]:", expected.st);
//                             $display("Got [st = %0d]:", st);
//                             // printTile(expected);
//                             // $finish(0); // Exits on failure
//                         end
//                     end
//                     default: begin
//                         $display("Expected tile, got something else");
//                         $finish(0);
//                     end
//                 endcase
//             end
//             tagged Tag_EndToken .et: begin
//                 $display("Test: End token received");
//                 $display("All tests completed at cycle %d", pmu.get_cycle_count());
//                 $finish(0);
//             end
//             default: begin
//                 $display("Expected Tag_Data in data_out");
//                 $finish(0);
//             end
//         endcase
//     endrule

// endmodule

// // ============================================================================
// // Stop token test with repeat module
// // ============================================================================
// // (* synthesize *)
// module mkTestPMUStopToken(Empty);
//     let rank = 3;
//     Vector#(10, Vector#(4, FIFOF#(MessageType))) dummy_fifos <- replicateM(replicateM(mkFIFOF));
//     PMU_IFC dut <- mkPMU(fromInteger(valueOf(RANK)), Coords { x: 0, y: 0 }, dummy_fifos[0], dummy_fifos[1], dummy_fifos[2], dummy_fifos[3], dummy_fifos[4], dummy_fifos[5], dummy_fifos[6], dummy_fifos[7], dummy_fifos[8], dummy_fifos[9]);
//     let rpt <- mkRepeatStatic(2);  
//     let drained <- mkReg(0);
    
//     Reg#(UInt#(32)) state <- mkReg(1);

//     rule push if (state % fromInteger(valueOf(ENTRY_SIZE)) != 0 && state < 10 * fromInteger(valueOf(ENTRY_SIZE)));
//         let data = tagged Tag_Data (tuple2(tagged Tag_Tile (0), 0));
//         dut.put_data(data);
//         state <= state + 1;
//     endrule

//     rule push_2 if (state % fromInteger(valueOf(ENTRY_SIZE)) == 0);
//         let data = tagged Tag_Data (tuple2(tagged Tag_Tile (1), rank));
//         dut.put_data(data);
//         state <= state + 1;
//         $display("pushed everything.");
//     endrule

//     rule token_output_to_repeat_input;
//         let data <- dut.get_token();
//         // data = tagged Tag_Data (tuple2(tpl_1(data.Tag_Data), tpl_2(data.Tag_Data) + 1));
//         $display("Forwarded to repeat.");
//         rpt.put(0, data);
//     endrule

//     rule repeat_output_to_pmu_input;
//         let data <- rpt.get(0);
//         // $display("Repeat output: ", fshow(data));
//         dut.put_token(data);
//     endrule

//     rule drain_result;
//         let data <- dut.get_data();
//         $display("data: ", fshow(data), "end.");
//         drained <= drained + 1;
//         // if (drained == 9) begin
//         //     $finish(0);
//         // end
//     endrule

// endmodule

module mkTestPMUGrid(Empty);

    // Create shared FIFOs for the mesh
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_request_data <- replicateM(replicateM(mkGFIFOF(False, False)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_request_data <- replicateM(replicateM(mkGFIFOF(False, False)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_send_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_send_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_request_space <- replicateM(replicateM(mkGFIFOF(True, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_request_space <- replicateM(replicateM(mkGFIFOF(True, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_send_space <- replicateM(replicateM(mkGFIFOF(False, False)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_send_space <- replicateM(replicateM(mkGFIFOF(False, False)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_send_dealloc <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_send_dealloc <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_send_update_pointer <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_send_update_pointer <- replicateM(replicateM(mkGFIFOF(False, True)));

    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_request_data <- replicateM(replicateM(mkGFIFOF(False, False)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_request_data <- replicateM(replicateM(mkGFIFOF(False, False)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_send_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_send_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_request_space <- replicateM(replicateM(mkGFIFOF(True, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_request_space <- replicateM(replicateM(mkGFIFOF(True, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_send_space <- replicateM(replicateM(mkGFIFOF(False, False)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_send_space <- replicateM(replicateM(mkGFIFOF(False, False)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_send_dealloc <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_send_dealloc <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_send_update_pointer <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_send_update_pointer <- replicateM(replicateM(mkGFIFOF(False, True)));
    // Instantiate the PMUs
    Vector#(NUM_PMUS, Vector#(NUM_PMUS, PMU_IFC)) pmus;

    Reg#(Bool) initialized <- mkReg(False);

    for (Integer i = 0; i < valueOf(NUM_PMUS); i = i + 1) begin
        for (Integer j = 0; j < valueOf(NUM_PMUS); j = j + 1) begin
            Vector#(4, FIFOF#(MessageType)) request_data = newVector();
            request_data[0] = sn_request_data[i][j];     // North
            request_data[1] = ns_request_data[i + 1][j]; // South
            request_data[2] = ew_request_data[i][j];     // West
            request_data[3] = we_request_data[i][j + 1]; // East

            Vector#(4, FIFOF#(MessageType)) receive_request_data = newVector();
            receive_request_data[0] = ns_request_data[i][j];     // North
            receive_request_data[1] = sn_request_data[i + 1][j]; // South
            receive_request_data[2] = we_request_data[i][j];     // West
            receive_request_data[3] = ew_request_data[i][j + 1]; // East

            Vector#(4, FIFOF#(MessageType)) send_data = newVector();
            send_data[0] = sn_send_data[i][j];
            send_data[1] = ns_send_data[i + 1][j];
            send_data[2] = ew_send_data[i][j];
            send_data[3] = we_send_data[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) receive_send_data = newVector();
            receive_send_data[0] = ns_send_data[i][j];
            receive_send_data[1] = sn_send_data[i + 1][j];
            receive_send_data[2] = we_send_data[i][j];
            receive_send_data[3] = ew_send_data[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) request_space = newVector();
            request_space[0] = sn_request_space[i][j];     // North
            request_space[1] = ns_request_space[i + 1][j]; // South
            request_space[2] = ew_request_space[i][j];     // West
            request_space[3] = we_request_space[i][j + 1]; // East

            Vector#(4, FIFOF#(MessageType)) receive_request_space = newVector();
            receive_request_space[0] = ns_request_space[i][j];     // North
            receive_request_space[1] = sn_request_space[i + 1][j]; // South
            receive_request_space[2] = we_request_space[i][j];     // West
            receive_request_space[3] = ew_request_space[i][j + 1]; // East

            Vector#(4, FIFOF#(MessageType)) send_space = newVector();
            send_space[0] = sn_send_space[i][j];
            send_space[1] = ns_send_space[i + 1][j];
            send_space[2] = ew_send_space[i][j];
            send_space[3] = we_send_space[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) receive_send_space = newVector();
            receive_send_space[0] = ns_send_space[i][j];
            receive_send_space[1] = sn_send_space[i + 1][j];
            receive_send_space[2] = we_send_space[i][j];
            receive_send_space[3] = ew_send_space[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) send_dealloc = newVector();
            send_dealloc[0] = sn_send_dealloc[i][j];
            send_dealloc[1] = ns_send_dealloc[i + 1][j];
            send_dealloc[2] = ew_send_dealloc[i][j];
            send_dealloc[3] = we_send_dealloc[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) receive_send_dealloc = newVector();
            receive_send_dealloc[0] = ns_send_dealloc[i][j];
            receive_send_dealloc[1] = sn_send_dealloc[i + 1][j];
            receive_send_dealloc[2] = we_send_dealloc[i][j];
            receive_send_dealloc[3] = ew_send_dealloc[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) send_update_pointer = newVector();
            send_update_pointer[0] = sn_send_update_pointer[i][j];
            send_update_pointer[1] = ns_send_update_pointer[i + 1][j];
            send_update_pointer[2] = ew_send_update_pointer[i][j];
            send_update_pointer[3] = we_send_update_pointer[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) receive_send_update_pointer = newVector();
            receive_send_update_pointer[0] = ns_send_update_pointer[i][j];
            receive_send_update_pointer[1] = sn_send_update_pointer[i + 1][j];
            receive_send_update_pointer[2] = we_send_update_pointer[i][j];
            receive_send_update_pointer[3] = ew_send_update_pointer[i][j + 1];

            pmus[i][j] <- mkPMU(
                fromInteger(valueOf(RANK)), // rank  
                Coords { x: fromInteger(j), y: fromInteger(i) }, // coords
                request_data,
                receive_request_data,
                send_data,
                receive_send_data,
                request_space,
                receive_request_space,
                send_space,
                receive_send_space,
                send_dealloc,
                receive_send_dealloc,
                send_update_pointer,
                receive_send_update_pointer
            );
        end
    end

    function TaggedTile testValues(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2))) i);
        Vector#(TILE_SIZE, Vector#(TILE_SIZE, Scalar)) mat = replicate(replicate(0));
        StopToken token = 0;
        // if (i == fromInteger(valueOf(NUM_TEST_VALUES) / 2 - 1)) begin
        //     token = 1;
        // end
        if (i == 3) begin
            token = 1;
        end
        if (i == fromInteger(valueOf(NUM_TEST_VALUES) - 1)) begin
            token = 2;
        end
        
        let cur = unpack(extend(i));
        let tile_size = fromInteger(valueOf(TILE_SIZE));
        let tile_size_squared = tile_size * tile_size;  
        for (Integer k = 0; k < valueOf(TILE_SIZE); k = k + 1) begin
            for (Integer l = 0; l < valueOf(TILE_SIZE); l = l + 1) begin
                mat[k][l] = tile_size_squared * cur + tile_size * fromInteger(k) + fromInteger(l);
            end
        end
        return TaggedTile { t: pack(mat), st: token };
    endfunction

    // === State tracking ===
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) putIndex <- mkReg(0);
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) getIndex <- mkReg(0);
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) valIndex <- mkReg(0);

    // === Put values ===
    rule driveInput (initialized);
        if (putIndex < fromInteger(valueOf(NUM_TEST_VALUES))) begin 
            pmus[1][1].put_data(tagged Tag_Data tuple2(tagged Tag_Tile testValues(putIndex).t, testValues(putIndex).st));
            // $display("Test: Putting value");
            // printTile(testValues[putIndex]);
            putIndex <= putIndex + 1;
        end else if (putIndex == fromInteger(valueOf(NUM_TEST_VALUES))) begin
            pmus[1][1].put_data(tagged Tag_EndToken 0);
            putIndex <= putIndex + 1;
            // $display("Test: Putting end token");
        end
    endrule

    // === Handle token output ===
    rule handleToken (initialized);
        let token <- pmus[1][1].get_token();
        case (token) matches
            tagged Tag_Data {.d, .st}: begin
                case (d) matches
                    tagged Tag_Ref {.r, .deallocate}: begin
                        // tokens.upd(getIndex, tuple2(r, deallocate));
                        $display("[TESTBENCH] Got token %d %d %d", r, deallocate, st);
                        getIndex <= getIndex + 1;
                        pmus[1][1].put_token(tagged Tag_Data tuple2(tagged Tag_Ref tuple2(r, False), st));
                    end
                    default: begin
                        $display("Expected scalar token, got something else");
                        $finish(0);
                    end
                endcase
            end
            tagged Tag_EndToken .et: begin
                $display("[TESTBENCH] End token received in token out");
                pmus[1][1].put_token(tagged Tag_EndToken 0);
            end
            default: begin
                $display("Expected Tag_Data in token_out");
                $finish(0);
            end
        endcase
    endrule

    // === Handle returned value ===
    rule handleValue (initialized);
        let value <- pmus[1][1].get_data();

        case (value) matches
            tagged Tag_Data {.d, .st}: begin
                case (d) matches
                    tagged Tag_Tile .t: begin
                        let expected = testValues(valIndex);
                        valIndex <= valIndex + 1;

                        if (TaggedTile { t: t, st: st } == expected) begin
                            $display("[TESTBENCH] PASSED:");
                            // printTile(TaggedTile { t: t, st: st });
                            $display("Expected [st = %0d]:", expected.st);
                            $display("Got [st = %0d]:", st);
                            // printTile(expected);
                        end else begin
                            $display("[TESTBENCH] FAILED:");
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
                $display("[TESTBENCH] End token received");
                $display("All tests completed at cycle %d", pmus[1][1].get_cycle_count());
                $finish(0);
            end
            default: begin
                $display("Expected Tag_Data in data_out");
                $finish(0);
            end
        endcase
    endrule

    rule print_grid_info (!initialized);
        $display("[GRID] Created %dx%d PMU grid", valueOf(NUM_PMUS), valueOf(NUM_PMUS));
        initialized <= True;
    endrule

endmodule

typedef 28 NUM_TEST_VALUES1;
typedef 17 NUM_TEST_VALUES2;

module mkTestPMUGrid2(Empty);

    // Create shared FIFOs for the mesh
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_request_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_request_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_send_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_send_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_request_space <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_request_space <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_send_space <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_send_space <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_send_dealloc <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_send_dealloc <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_send_update_pointer <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_send_update_pointer <- replicateM(replicateM(mkGFIFOF(False, True)));

    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_request_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_request_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_send_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_send_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_request_space <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_request_space <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_send_space <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_send_space <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_send_dealloc <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_send_dealloc <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_send_update_pointer <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_send_update_pointer <- replicateM(replicateM(mkGFIFOF(False, True)));
    // Instantiate the PMUs
    Vector#(NUM_PMUS, Vector#(NUM_PMUS, PMU_IFC)) pmus;

    Reg#(Bool) initialized <- mkReg(False);

    for (Integer i = 0; i < valueOf(NUM_PMUS); i = i + 1) begin
        for (Integer j = 0; j < valueOf(NUM_PMUS); j = j + 1) begin
            Vector#(4, FIFOF#(MessageType)) request_data = newVector();
            request_data[0] = sn_request_data[i][j];     // North
            request_data[1] = ns_request_data[i + 1][j]; // South
            request_data[2] = ew_request_data[i][j];     // West
            request_data[3] = we_request_data[i][j + 1]; // East

            Vector#(4, FIFOF#(MessageType)) receive_request_data = newVector();
            receive_request_data[0] = ns_request_data[i][j];     // North
            receive_request_data[1] = sn_request_data[i + 1][j]; // South
            receive_request_data[2] = we_request_data[i][j];     // West
            receive_request_data[3] = ew_request_data[i][j + 1]; // East

            Vector#(4, FIFOF#(MessageType)) send_data = newVector();
            send_data[0] = sn_send_data[i][j];
            send_data[1] = ns_send_data[i + 1][j];
            send_data[2] = ew_send_data[i][j];
            send_data[3] = we_send_data[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) receive_send_data = newVector();
            receive_send_data[0] = ns_send_data[i][j];
            receive_send_data[1] = sn_send_data[i + 1][j];
            receive_send_data[2] = we_send_data[i][j];
            receive_send_data[3] = ew_send_data[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) request_space = newVector();
            request_space[0] = sn_request_space[i][j];     // North
            request_space[1] = ns_request_space[i + 1][j]; // South
            request_space[2] = ew_request_space[i][j];     // West
            request_space[3] = we_request_space[i][j + 1]; // East

            Vector#(4, FIFOF#(MessageType)) receive_request_space = newVector();
            receive_request_space[0] = ns_request_space[i][j];     // North
            receive_request_space[1] = sn_request_space[i + 1][j]; // South
            receive_request_space[2] = we_request_space[i][j];     // West
            receive_request_space[3] = ew_request_space[i][j + 1]; // East

            Vector#(4, FIFOF#(MessageType)) send_space = newVector();
            send_space[0] = sn_send_space[i][j];
            send_space[1] = ns_send_space[i + 1][j];
            send_space[2] = ew_send_space[i][j];
            send_space[3] = we_send_space[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) receive_send_space = newVector();
            receive_send_space[0] = ns_send_space[i][j];
            receive_send_space[1] = sn_send_space[i + 1][j];
            receive_send_space[2] = we_send_space[i][j];
            receive_send_space[3] = ew_send_space[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) send_dealloc = newVector();
            send_dealloc[0] = sn_send_dealloc[i][j];
            send_dealloc[1] = ns_send_dealloc[i + 1][j];
            send_dealloc[2] = ew_send_dealloc[i][j];
            send_dealloc[3] = we_send_dealloc[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) receive_send_dealloc = newVector();
            receive_send_dealloc[0] = ns_send_dealloc[i][j];
            receive_send_dealloc[1] = sn_send_dealloc[i + 1][j];
            receive_send_dealloc[2] = we_send_dealloc[i][j];
            receive_send_dealloc[3] = ew_send_dealloc[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) send_update_pointer = newVector();
            send_update_pointer[0] = sn_send_update_pointer[i][j];
            send_update_pointer[1] = ns_send_update_pointer[i + 1][j];
            send_update_pointer[2] = ew_send_update_pointer[i][j];
            send_update_pointer[3] = we_send_update_pointer[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) receive_send_update_pointer = newVector();
            receive_send_update_pointer[0] = ns_send_update_pointer[i][j];
            receive_send_update_pointer[1] = sn_send_update_pointer[i + 1][j];
            receive_send_update_pointer[2] = we_send_update_pointer[i][j];
            receive_send_update_pointer[3] = ew_send_update_pointer[i][j + 1];

            pmus[i][j] <- mkPMU(
                fromInteger(valueOf(RANK)), // rank  
                Coords { x: fromInteger(j), y: fromInteger(i) }, // coords
                request_data,
                receive_request_data,
                send_data,
                receive_send_data,
                request_space,
                receive_request_space,
                send_space,
                receive_send_space,
                send_dealloc,
                receive_send_dealloc,
                send_update_pointer,
                receive_send_update_pointer
            );
        end
    end

    function TaggedTile testValues(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2))) i, Integer num_values);
        Vector#(TILE_SIZE, Vector#(TILE_SIZE, Scalar)) mat = replicate(replicate(0));
        StopToken token = 0;
        if (i == 3) begin
            token = 1;
        end
        if (i == fromInteger(num_values - 1)) begin
            token = 2;
        end
        
        let cur = unpack(extend(i));
        let tile_size = fromInteger(valueOf(TILE_SIZE));
        let tile_size_squared = tile_size * tile_size;  
        for (Integer k = 0; k < valueOf(TILE_SIZE); k = k + 1) begin
            for (Integer l = 0; l < valueOf(TILE_SIZE); l = l + 1) begin
                mat[k][l] = tile_size_squared * cur + tile_size * fromInteger(k) + fromInteger(l);
            end
        end
        return TaggedTile { t: pack(mat), st: token };
    endfunction

    // === State tracking ===
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) putIndex0 <- mkReg(0);
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) getIndex0 <- mkReg(0);
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) valIndex0 <- mkReg(0);

    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) putIndex1 <- mkReg(0);
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) getIndex1 <- mkReg(0);
    Reg#(Bit#(TLog#(TAdd#(NUM_TEST_VALUES, 2)))) valIndex1 <- mkReg(0);

    // === Put values ===
    rule driveInput (initialized);
        if (putIndex0 < fromInteger(valueOf(NUM_TEST_VALUES1))) begin 
            pmus[1][1].put_data(tagged Tag_Data tuple2(tagged Tag_Tile testValues(putIndex0, fromInteger(valueOf(NUM_TEST_VALUES1))).t, testValues(putIndex0, fromInteger(valueOf(NUM_TEST_VALUES1))).st));
            // $display("Test: Putting value");
            // printTile(testValues[putIndex]);
            putIndex0 <= putIndex0 + 1;
        end else if (putIndex0 == fromInteger(valueOf(NUM_TEST_VALUES1))) begin
            pmus[1][1].put_data(tagged Tag_EndToken 0);
            putIndex0 <= putIndex0 + 1;
            // $display("Test: Putting end token");
        end

        if (putIndex1 < fromInteger(valueOf(NUM_TEST_VALUES2))) begin 
            pmus[2][1].put_data(tagged Tag_Data tuple2(tagged Tag_Tile testValues(putIndex1, fromInteger(valueOf(NUM_TEST_VALUES2))).t, testValues(putIndex1, fromInteger(valueOf(NUM_TEST_VALUES2))).st));
            // $display("Test: Putting value");
            // printTile(testValues[putIndex]);
            putIndex1 <= putIndex1 + 1;
        end else if (putIndex1 == fromInteger(valueOf(NUM_TEST_VALUES2))) begin
            pmus[2][1].put_data(tagged Tag_EndToken 0);
            putIndex1 <= putIndex1 + 1;
            // $display("Test: Putting end token");
        end
    endrule

    // === Handle token output ===
    rule handleToken0 (initialized);
        let token <- pmus[1][1].get_token();
        case (token) matches
            tagged Tag_Data {.d, .st}: begin
                case (d) matches
                    tagged Tag_Ref {.r, .deallocate}: begin
                        // tokens.upd(getIndex, tuple2(r, deallocate));
                        $display("[TESTBENCH] Got token %d %d %d", r, deallocate, st);
                        getIndex0 <= getIndex0 + 1;
                        pmus[1][1].put_token(tagged Tag_Data tuple2(tagged Tag_Ref tuple2(r, False), st));
                    end
                    default: begin
                        $display("Expected scalar token, got something else");
                        $finish(0);
                    end
                endcase
            end
            tagged Tag_EndToken .et: begin
                $display("[TESTBENCH] End token received in token out");
                pmus[1][1].put_token(tagged Tag_EndToken 0);
            end
            default: begin
                $display("Expected Tag_Data in token_out");
                $finish(0);
            end
        endcase
    endrule

    rule handleToken1 (initialized);
        let token <- pmus[2][1].get_token();
        case (token) matches
            tagged Tag_Data {.d, .st}: begin
                case (d) matches
                    tagged Tag_Ref {.r, .deallocate}: begin
                        // tokens.upd(getIndex, tuple2(r, deallocate));
                        $display("[TESTBENCH] Got token %d %d %d", r, deallocate, st);
                        getIndex1 <= getIndex1 + 1;
                        pmus[2][1].put_token(tagged Tag_Data tuple2(tagged Tag_Ref tuple2(r, False), st));
                    end
                    default: begin
                        $display("Expected scalar token, got something else");
                        $finish(0);
                    end
                endcase
            end
            tagged Tag_EndToken .et: begin
                $display("[TESTBENCH] End token received in token out");
                pmus[2][1].put_token(tagged Tag_EndToken 0);
            end
            default: begin
                $display("Expected Tag_Data in token_out");
                $finish(0);
            end
        endcase
    endrule

    // === Handle returned value ===
    rule handleValue0 (initialized);
        let value <- pmus[1][1].get_data();

        case (value) matches
            tagged Tag_Data {.d, .st}: begin
                case (d) matches
                    tagged Tag_Tile .t: begin
                        let expected = testValues(valIndex0, fromInteger(valueOf(NUM_TEST_VALUES1)));
                        valIndex0 <= valIndex0 + 1;

                        if (TaggedTile { t: t, st: st } == expected) begin
                            $display("[TESTBENCH] PASSED:");
                            // printTile(TaggedTile { t: t, st: st });
                            $display("Expected [st = %0d]:", expected.st);
                            $display("Got [st = %0d]:", st);
                            // printTile(expected);
                        end else begin
                            $display("[TESTBENCH] FAILED:");
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
                $display("[TESTBENCH] End token received");
                $display("All tests completed at cycle %d", pmus[1][1].get_cycle_count());
                // $finish(0);
            end
            default: begin
                $display("Expected Tag_Data in data_out");
                $finish(0);
            end
        endcase
    endrule

    rule handleValue1 (initialized);
        let value <- pmus[2][1].get_data();

        case (value) matches
            tagged Tag_Data {.d, .st}: begin
                case (d) matches
                    tagged Tag_Tile .t: begin
                        let expected = testValues(valIndex1, fromInteger(valueOf(NUM_TEST_VALUES2)));
                        valIndex1 <= valIndex1 + 1;

                        if (TaggedTile { t: t, st: st } == expected) begin
                            $display("[TESTBENCH] PASSED:");
                            // printTile(TaggedTile { t: t, st: st });
                            $display("Expected [st = %0d]:", expected.st);
                            $display("Got [st = %0d]:", st);
                            // printTile(expected);
                        end else begin
                            $display("[TESTBENCH] FAILED:");
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
                $display("[TESTBENCH] End token received");
                $display("All tests completed at cycle %d", pmus[1][1].get_cycle_count());
                // $finish(0);
            end
            default: begin
                $display("Expected Tag_Data in data_out");
                $finish(0);
            end
        endcase
    endrule

    rule print_grid_info (!initialized);
        $display("[GRID] Created %dx%d PMU grid", valueOf(NUM_PMUS), valueOf(NUM_PMUS));
        initialized <= True;
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