package TestMatmul;

import Vector::*;
import FIFO::*;
import StmtFSM::*;
import TestTypes::*;
import Matmul::*;
import Types::*;
import Parameters::*;

// Test 1: Basic Matrix Multiplication Test
module mkTestBasicMatmul(TestRunner);
    Matmul_IFC matmul <- mkSpatialMatmulT(0, 1, False, False);
    
    Reg#(Int#(32)) cycle_count <- mkReg(0);
    Reg#(TestResult) test_result <- mkReg(TestIncomplete);
    Reg#(String) test_message <- mkReg("");
    
    // Test data
    Tile a_tile = create_test_tile(1);
    Tile b_tile = create_test_tile(10);
    Tile expected_result = matmul_t_tile(a_tile, b_tile);
    
    Stmt test_seq = seq
        $display("=== Test 1: Basic Matrix Multiplication ===");
        
        // Put test data
        matmul.put_a(create_tagged_tile(1, 0));
        matmul.put_b(create_tagged_tile(10, 0));
        
        // Get result
        let result <- matmul.get_psum();
        
        // Check result
        if (tiles_equal(result.t, expected_result)) begin
            test_result <= TestPass;
            test_message <= "Basic matrix multiplication passed";
        end else begin
            test_result <= TestFail;
            test_message <= "Basic matrix multiplication failed - result mismatch";
        end
        
        cycle_count <= cycle_count + 1;
    endseq;
    
    FSM test_fsm <- mkFSM(test_seq);
    
    rule run_test;
        test_fsm.start();
    endrule
    
    method Action start_test(String test_name);
        test_fsm.start();
    endmethod
    
    method Action end_test(TestResult result, String message);
        test_result <= result;
        test_message <= message;
    endmethod
    
    method ActionValue#(TestStatus) get_test_status();
        return TestStatus {
            test_name: "Basic Matrix Multiplication",
            result: test_result,
            message: test_message,
            cycles: cycle_count
        };
    endmethod
    
    method Bool all_tests_passed();
        return test_result == TestPass;
    endmethod
    
endmodule

// Test 2: Partial Sum Accumulation Test
module mkTestPartialSum(TestRunner);
    Matmul_IFC matmul <- mkSpatialMatmulT(0, 1, True, False);
    
    Reg#(Int#(32)) cycle_count <- mkReg(0);
    Reg#(TestResult) test_result <- mkReg(TestIncomplete);
    Reg#(String) test_message <- mkReg("");
    
    // Test data
    Tile a_tile = create_test_tile(1);
    Tile b_tile = create_test_tile(10);
    Tile psum_tile = create_test_tile(100);
    Tile expected_result = add_tile(matmul_t_tile(a_tile, b_tile), psum_tile);
    
    Stmt test_seq = seq
        $display("=== Test 2: Partial Sum Accumulation ===");
        
        // Put test data
        matmul.put_a(create_tagged_tile(1, 0));
        matmul.put_b(create_tagged_tile(10, 0));
        matmul.put_psum(create_tagged_tile(100, 0));
        
        // Get result
        let result <- matmul.get_psum();
        
        // Check result
        if (tiles_equal(result.t, expected_result)) begin
            test_result <= TestPass;
            test_message <= "Partial sum accumulation passed";
        end else begin
            test_result <= TestFail;
            test_message <= "Partial sum accumulation failed - result mismatch";
        end
        
        cycle_count <= cycle_count + 1;
    endseq;
    
    FSM test_fsm <- mkFSM(test_seq);
    
    rule run_test;
        test_fsm.start();
    endrule
    
    method Action start_test(String test_name);
        test_fsm.start();
    endmethod
    
    method Action end_test(TestResult result, String message);
        test_result <= result;
        test_message <= message;
    endmethod
    
    method ActionValue#(TestStatus) get_test_status();
        return TestStatus {
            test_name: "Partial Sum Accumulation",
            result: test_result,
            message: test_message,
            cycles: cycle_count
        };
    endmethod
    
    method Bool all_tests_passed();
        return test_result == TestPass;
    endmethod
    
endmodule

// Test 3: Weight Forwarding Test
module mkTestWeightForwarding(TestRunner);
    Matmul_IFC matmul <- mkSpatialMatmulT(2, 1, False, False); // row_position = 2
    
    Reg#(Int#(32)) cycle_count <- mkReg(0);
    Reg#(TestResult) test_result <- mkReg(TestIncomplete);
    Reg#(String) test_message <- mkReg("");
    Reg#(Int#(32)) weights_sent <- mkReg(0);
    
    Stmt test_seq = seq
        $display("=== Test 3: Weight Forwarding ===");
        
        // Send 3 weights (2 should be forwarded, 1 should be used)
        matmul.put_b(create_tagged_tile(10, 0)); // Should be forwarded
        matmul.put_b(create_tagged_tile(20, 0)); // Should be forwarded
        matmul.put_b(create_tagged_tile(30, 0)); // Should be used
        
        // Check that 2 weights were forwarded
        let forwarded_1 <- matmul.get_b();
        let forwarded_2 <- matmul.get_b();
        
        if (forwarded_1.t == create_test_tile(10) && forwarded_2.t == create_test_tile(20)) begin
            test_result <= TestPass;
            test_message <= "Weight forwarding passed";
        end else begin
            test_result <= TestFail;
            test_message <= "Weight forwarding failed - incorrect forwarding";
        end
        
        cycle_count <= cycle_count + 1;
    endseq;
    
    FSM test_fsm <- mkFSM(test_seq);
    
    rule run_test;
        test_fsm.start();
    endrule
    
    method Action start_test(String test_name);
        test_fsm.start();
    endmethod
    
    method Action end_test(TestResult result, String message);
        test_result <= result;
        test_message <= message;
    endmethod
    
    method ActionValue#(TestStatus) get_test_status();
        return TestStatus {
            test_name: "Weight Forwarding",
            result: test_result,
            message: test_message,
            cycles: cycle_count
        };
    endmethod
    
    method Bool all_tests_passed();
        return test_result == TestPass;
    endmethod
    
endmodule

// Test 4: Multiple Row Processing Test
module mkTestMultipleRows(TestRunner);
    Matmul_IFC matmul <- mkSpatialMatmulT(0, 3, False, False); // num_rows = 3
    
    Reg#(Int#(32)) cycle_count <- mkReg(0);
    Reg#(TestResult) test_result <- mkReg(TestIncomplete);
    Reg#(String) test_message <- mkReg("");
    Reg#(Int#(32)) rows_processed <- mkReg(0);
    
    Stmt test_seq = seq
        $display("=== Test 4: Multiple Row Processing ===");
        
        // Put weight
        matmul.put_b(create_tagged_tile(10, 0));
        
        // Process 3 rows
        matmul.put_a(create_tagged_tile(1, 0));
        let result_1 <- matmul.get_psum();
        rows_processed <= rows_processed + 1;
        
        matmul.put_a(create_tagged_tile(2, 0));
        let result_2 <- matmul.get_psum();
        rows_processed <= rows_processed + 1;
        
        matmul.put_a(create_tagged_tile(3, 0));
        let result_3 <- matmul.get_psum();
        rows_processed <= rows_processed + 1;
        
        // Verify results
        Tile expected_1 = matmul_t_tile(create_test_tile(1), create_test_tile(10));
        Tile expected_2 = matmul_t_tile(create_test_tile(2), create_test_tile(10));
        Tile expected_3 = matmul_t_tile(create_test_tile(3), create_test_tile(10));
        
        if (tiles_equal(result_1.t, expected_1) && 
            tiles_equal(result_2.t, expected_2) && 
            tiles_equal(result_3.t, expected_3)) begin
            test_result <= TestPass;
            test_message <= "Multiple row processing passed";
        end else begin
            test_result <= TestFail;
            test_message <= "Multiple row processing failed - result mismatch";
        end
        
        cycle_count <= cycle_count + 1;
    endseq;
    
    FSM test_fsm <- mkFSM(test_seq);
    
    rule run_test;
        test_fsm.start();
    endrule
    
    method Action start_test(String test_name);
        test_fsm.start();
    endmethod
    
    method Action end_test(TestResult result, String message);
        test_result <= result;
        test_message <= message;
    endmethod
    
    method ActionValue#(TestStatus) get_test_status();
        return TestStatus {
            test_name: "Multiple Row Processing",
            result: test_result,
            message: test_message,
            cycles: cycle_count
        };
    endmethod
    
    method Bool all_tests_passed();
        return test_result == TestPass;
    endmethod
    
endmodule

// Test 5: Stop Token Propagation Test
module mkTestStopToken(TestRunner);
    Matmul_IFC matmul <- mkSpatialMatmulT(0, 1, False, True); // bottom_right = True
    
    Reg#(Int#(32)) cycle_count <- mkReg(0);
    Reg#(TestResult) test_result <- mkReg(TestIncomplete);
    Reg#(String) test_message <- mkReg("");
    
    Stmt test_seq = seq
        $display("=== Test 5: Stop Token Propagation ===");
        
        // Put test data with stop token
        matmul.put_a(create_tagged_tile(1, 42)); // stop token = 42
        matmul.put_b(create_tagged_tile(10, 0));
        
        // Get result
        let result <- matmul.get_psum();
        
        // Check that stop token is propagated correctly
        if (result.st == 42) begin
            test_result <= TestPass;
            test_message <= "Stop token propagation passed";
        end else begin
            test_result <= TestFail;
            test_message <= "Stop token propagation failed - incorrect stop token";
        end
        
        cycle_count <= cycle_count + 1;
    endseq;
    
    FSM test_fsm <- mkFSM(test_seq);
    
    rule run_test;
        test_fsm.start();
    endrule
    
    method Action start_test(String test_name);
        test_fsm.start();
    endmethod
    
    method Action end_test(TestResult result, String message);
        test_result <= result;
        test_message <= message;
    endmethod
    
    method ActionValue#(TestStatus) get_test_status();
        return TestStatus {
            test_name: "Stop Token Propagation",
            result: test_result,
            message: test_message,
            cycles: cycle_count
        };
    endmethod
    
    method Bool all_tests_passed();
        return test_result == TestPass;
    endmethod
    
endmodule

endpackage 