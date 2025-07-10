package Float;

import FloatingPoint::*;

/*
typedef struct {
    Bit#(32) value;
} Float deriving(Bits, Eq);

import "BDPI" function Float c_fadd(Float a, Float b);
import "BDPI" function Float c_fsub(Float a, Float b);
import "BDPI" function Float c_fmul(Float a, Float b);
import "BDPI" function Float c_fdiv(Float a, Float b);
import "BDPI" function Float c_sqrt_f(Float a);
import "BDPI" function Float c_d2f(Bit#(64) a);
import "BDPI" function Float c_i2f(Bit#(32) a);

function Float \+ (Float a, Float b);
    return c_fadd(a, b);
endfunction

function Float \- (Float a, Float b);
    return c_fsub(a, b);
endfunction
// 
// instance Mul#(Float);
//     function Float mul(Float a, Float b);
//         return c_fmul(a, b);
//     endfunction
// endinstance
// 
// instance Div#(Float);
//     function Float div(Float a, Float b);
//         return c_fdiv(a, b);
//     endfunction
// endinstance

function Float fromReal(Real x);
    Bit#(64) bits = $realtobits(x);
    return c_d2f(bits);
endfunction
    
    */
endpackage