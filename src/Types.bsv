package Types;

import Parameters::*;
import Vector::*;

typedef Int#(32) StopToken;
typedef Int#(32) Scalar;

typedef 4 TILE_SIZE;
typedef TMul#(TILE_SIZE, TILE_SIZE) TILE_SIZE_SQUARE;
typedef Bit#(TMul#(TILE_SIZE, TMul#(TILE_SIZE, SizeOf#(Scalar)))) Tile;

/*
function Tile add_tile (Tile a, Tile b);
    for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1) begin
        for (Integer j = 0; j < valueOf(TILE_SIZE); j = j + 1) begin
            a[i][j] = a[i][j] + b[i][j];
        end
    end
    return a;
endfunction

function Tile sub_tile (Tile a, Tile b);
    for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1) begin
        for (Integer j = 0; j < valueOf(TILE_SIZE); j = j + 1) begin
            a[i][j] = a[i][j] - b[i][j];
        end
    end
    return a;
endfunction

function Tile mul_tile (Tile a, Tile b);
    for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1) begin
        for (Integer j = 0; j < valueOf(TILE_SIZE); j = j + 1) begin
            a[i][j] = a[i][j] * b[i][j];
        end
    end
    return a;
endfunction

function Tile div_tile (Tile a, Tile b);
    for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1) begin
        for (Integer j = 0; j < valueOf(TILE_SIZE); j = j + 1) begin
            a[i][j] = a[i][j] / b[i][j];
        end
    end
    return a;
endfunction
*/

// a * b^T
/*
function Tile matmul_t_tile(Tile a, Tile b);
    Tile result = replicate(replicate(0));
    for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1) begin
        for (Integer j = 0; j < valueOf(TILE_SIZE); j = j + 1) begin
            Scalar sum = 0;
            for (Integer k = 0; k < valueOf(TILE_SIZE); k = k + 1) begin
                sum = sum + a[i][k] * b[j][k];
            end
            result[i][j] = sum;
        end
    end
    return result;
endfunction
*/

typedef TMul#(TMul#(TILE_SIZE, TILE_SIZE), 32) TileBits;
import "BDPI" function Bit#(TileBits) matmul_t_tile_c(Bit#(TileBits) a, Bit#(TileBits) b, Int#(32) tile_size);
import "BDPI" function Bit#(TileBits) add_tile_c(Bit#(TileBits) a, Bit#(TileBits) b, Int#(32) tile_size);
import "BDPI" function Bit#(TileBits) sub_tile_c(Bit#(TileBits) a, Bit#(TileBits) b, Int#(32) tile_size);
import "BDPI" function Bit#(TileBits) mul_tile_c(Bit#(TileBits) a, Bit#(TileBits) b, Int#(32) tile_size);
import "BDPI" function Bit#(TileBits) div_tile_c(Bit#(TileBits) a, Bit#(TileBits) b, Int#(32) tile_size);
import "BDPI" function Bit#(TileBits) silu_tile_c(Bit#(TileBits) a, Int#(32) tile_size);

function Tile matmul_t_tile(Tile a, Tile b);
    Bit#(TileBits) a_packed = pack(a);
    Bit#(TileBits) b_packed = pack(b);

    let v = matmul_t_tile_c(a_packed, b_packed, fromInteger(valueOf(TILE_SIZE)));

    return unpack(v);
endfunction

function Tile add_tile(Tile a, Tile b);
    Bit#(TileBits) a_packed = pack(a);
    Bit#(TileBits) b_packed = pack(b);

    let v = add_tile_c(a_packed, b_packed, fromInteger(valueOf(TILE_SIZE)));

    return unpack(v);
endfunction

function Tile sub_tile(Tile a, Tile b);
    Bit#(TileBits) a_packed = pack(a);
    Bit#(TileBits) b_packed = pack(b);

    let v = sub_tile_c(a_packed, b_packed, fromInteger(valueOf(TILE_SIZE)));

    return unpack(v);
endfunction

function Tile mul_tile(Tile a, Tile b);
    Bit#(TileBits) a_packed = pack(a);
    Bit#(TileBits) b_packed = pack(b);

    let v = mul_tile_c(a_packed, b_packed, fromInteger(valueOf(TILE_SIZE)));

    return unpack(v);
endfunction

function Tile div_tile(Tile a, Tile b);
    Bit#(TileBits) a_packed = pack(a);
    Bit#(TileBits) b_packed = pack(b);

    let v = div_tile_c(a_packed, b_packed, fromInteger(valueOf(TILE_SIZE)));

    return unpack(v);
endfunction

function Tile silu_tile(Tile a);
    Bit#(TileBits) a_packed = pack(a);
    let v = silu_tile_c(a_packed, fromInteger(valueOf(TILE_SIZE)));
    return unpack(v);
endfunction

/*
function Tile matmul_tile (Tile a, Tile b);
    Tile result = replicate(replicate(0));
    for (Integer i = 0; i < valueOf(TILE_SIZE); i = i + 1) begin
        for (Integer j = 0; j < valueOf(TILE_SIZE); j = j + 1) begin
            for (Integer k = 0; k < valueOf(TILE_SIZE); k = k + 1) begin
                result[i][j] = result[i][j] + a[i][k] * b[k][j];
            end
        end
    end
    return result;
endfunction
*/

typedef Bit#(32) Ref_Inner;
typedef Tuple2#(Ref_Inner, Bool) Ref; // Reference, deallocate
typedef Bit#(0) EndToken;

typedef struct {
    Tile t;
    StopToken st;
} TaggedTile deriving (Bits, Eq, FShow);

typedef union tagged {
    Tile Tag_Tile;
    Ref Tag_Ref;
    Scalar Tag_Scalar;
} Data deriving (Bits, Eq, FShow);

typedef struct {
    UInt#(16) ptr;
    UInt#(16) port_idx;
} Instruction_Ptr deriving (Bits, FShow);

typedef union tagged {
    Tuple2#(Data, StopToken) Tag_Data;
    Instruction_Ptr Tag_Instruction;
    EndToken Tag_EndToken;
} ChannelMessage deriving (Bits, FShow);

typedef UInt#(TLog#(NUM_PMUS)) CoordType;

typedef struct {
    UInt#(TLog#(SETS)) set;
    FRAME_INDEX frame;
    CoordType x;
    CoordType y;
} StorageAddr deriving(Bits, Eq, FShow);


typedef struct {
    StorageAddr loc;
    Bool deallocate;
    StopToken st;
    Bit#(TLog#(MAX_ENTRIES)) orig_token;
} LoadState deriving(Bits, Eq);

typedef enum {
    North, 
    South, 
    East, 
    West
} Direction deriving(Bits, Eq, FShow);

typedef struct {
    CoordType x;
    CoordType y;
} Coords deriving(Bits, Eq);

typedef struct {
    TaggedTile data;
    StorageAddr loc;
    Maybe#(StorageAddr) next;
} DataWithNext deriving(Bits, Eq, FShow);

typedef struct {
    StorageAddr loc;
    Bool deallocate;
} RequestStorageAddr deriving(Bits, Eq, FShow);

typedef struct {
    StorageAddr prev;
    StorageAddr next;
} PrevToNextTag deriving(Bits, Eq, FShow);

typedef union tagged {
    // TODO: Add message types like free space no, free space request, request_data, maybe others?
    StorageAddr Tag_FreeSpaceYes;
    void Tag_FreeSpaceNo;
    DataWithNext Tag_Store;
    DataWithNext Tag_Load;
    EndToken Tag_EndToken;
    StorageAddr Tag_Deallocate;
    RequestStorageAddr Tag_Request_Data;
    PrevToNextTag Tag_Update_Next_Table;
} MessageType deriving(Bits, Eq, FShow);

endpackage