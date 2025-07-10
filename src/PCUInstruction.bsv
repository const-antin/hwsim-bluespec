package PCUInstruction;

import Types::*;
import Vector::*;
import Parameters::*;

typedef enum {
    ADD, SUB, MUL, DIV, 
    MATMUL_T, MATMUL
} ALUOp deriving (Bits, Eq, FShow);

typedef struct {
    ALUOp op;
    Int#(TLog#(NUM_INPUTS_PER_STAGE)) input_a;
    Int#(TLog#(NUM_INPUTS_PER_STAGE)) input_b;
    Int#(TLog#(NUM_INPUTS_PER_STAGE)) input_c;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out;
    Int#(32) id;
} Map deriving (Bits, Eq, FShow);

typedef struct {
    ALUOp op;
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out;
    StopToken rank;
    Scalar init;
    Int#(32) id;
} Accumulate deriving (Bits, Eq, FShow);

typedef struct {
    Int#(TLog#(NUM_INPUTS_PER_STAGE)) inputs;
    Vector#(NUM_OUTPUTS_PER_STAGE, Bool) out;
    Int#(32) id;
} Broadcast deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out;
    StopToken rank;
    Int#(32) id;
} Concat deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out_counter;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out_data;
    StopToken rank;
    Int#(32) id;
} Enumerate deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out;
    StopToken rank;
    Int#(32) id;
} Flatten deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out;
    StopToken rank;
    Int#(32) id;
} Flatmap deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out;
    StopToken rank;
    Int#(32) id;
} RepeatN deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out;
    StopToken rank;
    Int#(32) id;
} RepeatRef deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out;
    StopToken rank;
    Int#(32) count;
    Int#(32) id;
} RepeatStatic deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out;
    StopToken rank;
    Int#(32) id;
} Reshape deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out;
    StopToken rank;
    Int#(32) id;
} Reassemble deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Vector#(NUM_OUTPUTS_PER_STAGE, Bool) outputs;
    StopToken rank;
    Int#(32) id;
} Rotate deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Vector#(NUM_OUTPUTS_PER_STAGE, Bool) outputs;
    StopToken rank;
    Int#(32) id;
} Parallelize deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Vector#(NUM_OUTPUTS_PER_STAGE, Bool) outputs;
    StopToken rank;
    Int#(32) id;
} Partition deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out;
    StopToken rank;
    Int#(32) id;
} Promote deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out;
    StopToken rank;
    Int#(32) id;
} Scan deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out_weight;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out_data;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out_partial;
    StopToken rank;
    Int#(32) id;
} SpatialMatmulT deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_STAGE, Bool) inputs;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out_weight;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out_data;
    Int#(TLog#(NUM_OUTPUTS_PER_STAGE)) out_partial;
    StopToken rank;
    Int#(32) id;
} SpatialMatmul deriving (Bits, Eq, FShow);

typedef union tagged {
    Map Map_t;
    Accumulate Accumulate_t;
    Broadcast Broadcast_t;
    Concat Concat_t;
    Enumerate Enumerate_t;
    Flatten Flatten_t;
    Flatmap Flatmap_t;
    RepeatN RepeatN_t;
    RepeatRef RepeatRef_t;
    RepeatStatic RepeatStatic_t;
    Reshape Reshape_t;
    Reassemble Reassemble_t;
    Rotate Rotate_t;
    Parallelize Parallelize_t;
    Partition Partition_t;
    Promote Promote_t;
    Scan Scan_t;
    SpatialMatmulT SpatialMatmulT_t;
    SpatialMatmul SpatialMatmul_t;
} StageConfig deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_PCU, Bool) dequeue_from_input;
    Vector#(NUM_OUTPUTS_PER_PCU, Bool) enqueue_to_output;
    Vector#(NUM_STAGES, StageConfig) stage_configs;
    Int#(32) debug_id;
} Instruction deriving (Bits, Eq, FShow);

endpackage