import Types::*;
import Parameters::*;
import Vector::*;

typedef enum {
    ADD, SUB, MUL, DIV, 
    MATMUL_T, MATMUL
} ALUOp deriving (Bits, Eq, FShow);

typedef struct {
    ALUOp op;
} BinaryMapConfig deriving (Bits, Eq, FShow);

typedef struct {
    ALUOp op;
} UnaryMapConfig deriving (Bits, Eq, FShow);

typedef struct {
    ALUOp op;
} TernaryMapConfig deriving (Bits, Eq, FShow);

typedef struct {
    ALUOp op;
    StopToken rank;
} AccumulateBigTileConfig deriving (Bits, Eq, FShow);

typedef struct {
    ALUOp op;
    StopToken rank;
    Scalar init;
} AccumulateConfig deriving (Bits, Eq, FShow);

typedef struct {
} BroadcastConfig deriving (Bits, Eq, FShow);

typedef struct {
    StopToken rank;
} ConcatConfig deriving (Bits, Eq, FShow);

typedef struct {
    StopToken rank;
} EnumerateConfig deriving (Bits, Eq, FShow);

typedef struct {
    StopToken rank;
} FlattenConfig deriving (Bits, Eq, FShow);

typedef struct {
    StopToken rank;
} FlatMapConfig deriving (Bits, Eq, FShow);

typedef struct {
    UInt#(32) count;
} RepeatNConfig deriving (Bits, Eq, FShow);

typedef struct {
    StopToken rank;
} RepeatRefConfig deriving (Bits, Eq, FShow);

typedef struct {
    UInt#(16) count;
} RepeatStaticConfig deriving (Bits, Eq, FShow);

typedef struct {
    UInt#(16) split_dim;
    UInt#(16) chunk_size;
    Maybe#(Tile) elem;
} ReshapeConfig deriving (Bits, Eq, FShow);

typedef struct {
    StopToken rank;
} ReassembleConfig deriving (Bits, Eq, FShow);

typedef struct {
    StopToken reset_rank;
} RotateConfig deriving (Bits, Eq, FShow);

typedef struct {
    StopToken rank;
} ParallelizeConfig deriving (Bits, Eq, FShow);

typedef struct {
    StopToken rank;
} PartitionConfig deriving (Bits, Eq, FShow);

typedef struct {
    StopToken rank;
} PromoteConfig deriving (Bits, Eq, FShow);

typedef struct {
    ALUOp op;
    Maybe#(Scalar) init;
    StopToken rank;
} ScanConfig deriving (Bits, Eq, FShow);

typedef struct {
    UInt#(16) row_position;
    UInt#(16) num_rows;
    Bool bottom_right;
} SpatialMatmulTConfig deriving (Bits, Eq, FShow);

// The tagged union for all instructions
typedef union tagged {
    UnaryMapConfig Tag_UnaryMap;
    BinaryMapConfig Tag_BinaryMap;
    AccumulateBigTileConfig Tag_AccumulateBigTile;
    AccumulateConfig Tag_Accumulate;
    BroadcastConfig Tag_Broadcast;
    ConcatConfig Tag_Concat;
    EnumerateConfig Tag_Enumerate;
    FlattenConfig Tag_Flatten;
    FlatMapConfig Tag_FlatMap;
    RepeatNConfig Tag_RepeatN;
    RepeatRefConfig Tag_RepeatRef;
    RepeatStaticConfig Tag_RepeatStatic;
    ReshapeConfig Tag_Reshape;
    ReassembleConfig Tag_Reassemble;
    RotateConfig Tag_Rotate;
    ParallelizeConfig Tag_Parallelize;
    PartitionConfig Tag_Partition;
    PromoteConfig Tag_Promote;
    ScanConfig Tag_Scan;
    SpatialMatmulTConfig Tag_SpatialMatmulT;
} InstructionOp deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(NUM_INPUTS_PER_PCU, Maybe#(UInt#(TLog#(NUM_INPUTS_PER_PCU)))) input_ports;
    Vector#(NUM_OUTPUTS_PER_PCU, Maybe#(UInt#(TLog#(NUM_OUTPUTS_PER_PCU)))) output_ports;
    InstructionOp op;
    UInt#(32) debug_id;
} Instruction deriving (Bits, Eq, FShow);