`define PASTE2(x, y) x``y 

`define UNROLL_4(i) \
    `i(0) \
    `i(1) \
    `i(2) \
    `i(3) \

`define RULE_SPACE_REQUEST_NO(i) \
    rule `PASTE2(space_request_no_, i) (initialized &&& (!isValid(next_free_set) || space_request_in_flight || (isValid(next_free_set) &&& (next_free_set.Valid.x != coords.x || next_free_set.Valid.y != coords.y)))); \
        receive_request_space[i].deq; \
        send_space[i].enq(tagged Tag_FreeSpaceNo); \
    endrule 

`define RULE_SEND_DEALLOC_NO(i) \
    rule `PASTE2(send_dealloc_, i); \
        if (dealloc_wire[i] matches tagged Valid .loc) begin \
            send_dealloc[i].enq(tagged Tag_Deallocate dealloc_wire[i].Valid); \
        end \
    endrule

`define RULE_NEXT_FREE(i) \
    rule `PASTE2(next_free_, i) (send_request_space_wire[i]); \
        request_space[i].enq(tagged Tag_EndToken 0); \
    endrule