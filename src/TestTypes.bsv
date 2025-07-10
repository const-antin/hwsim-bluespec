package TestTypes;

import Vector::*;
import Types::*;
import Parameters::*;

// Test result types
typedef enum {
    TestPass,
    TestFail,
    TestIncomplete
} TestResult deriving (Bits, Eq, FShow);

// Test status
typedef struct {
    String test_name;
    TestResult result;
    String message;
    Int#(32) cycles;
} TestStatus deriving (Bits, FShow);

// Test configuration
typedef struct {
    String test_name;
    Bool verbose;
    Int#(32) max_cycles;
} TestConfig deriving (Bits, FShow);

// Test data generators
interface TestDataGen#(type t);
    method ActionValue#(t) generate_data();
    method Bool is_done();
endinterface

// Test checker interface
interface TestChecker#(type t);
    method Action put_result(t result);
    method ActionValue#(TestResult) get_verdict();
endinterface

// Test runner interface
interface TestRunner;
    method Action start_test(String test_name);
    method Action end_test(TestResult result, String message);
    method ActionValue#(TestStatus) get_test_status();
    method Bool all_tests_passed();
endinterface

// Helper functions for test data generation
function Tile create_test_tile(Int#(32) base_value);
    Tile tile = replicate(replicate(0));
    for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1) begin
        for (Integer j = 0; j < valueOf(TILE_SIZE); j = j + 1) begin
            tile[i][j] = base_value + fromInteger(i * valueOf(TILE_SIZE) + j);
        end
    end
    return tile;
endfunction

function TaggedTile create_tagged_tile(Int#(32) base_value, StopToken st);
    return TaggedTile { t: create_test_tile(base_value), st: st };
endfunction

// Test utilities
function Bool tiles_equal(Tile a, Tile b);
    Bool equal = True;
    for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1) begin
        for (Integer j = 0; j < valueOf(TILE_SIZE); j = j + 1) begin
            if (a[i][j] != b[i][j]) begin
                equal = False;
            end
        end
    end
    return equal;
endfunction

function String tile_to_string(Tile tile);
    String s = "Tile:\n";
    for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1) begin
        s = s + "  ";
        for (Integer j = 0; j < valueOf(TILE_SIZE); j = j + 1) begin
            s = s + " " + integerToString(tile[i][j]);
        end
        s = s + "\n";
    end
    return s;
endfunction

endpackage 