import "BDPI" function Action ramulator_wrapper_init();
import "BDPI" function Action ramulator_wrapper_free();
import "BDPI" function Action ramulator_wrapper_send(Bit#(64) addr, Bool is_write);
import "BDPI" function Action ramulator_wrapper_tick();
import "BDPI" function Action ramulator_wrapper_get_cycle();
import "BDPI" function Action ramulator_wrapper_ret_available();
import "BDPI" function ActionValue#(Bit#(64)) ramulator_wrapper_pop();
import "BDPI" function ActionValue#(Bool) ramulator_wrapper_is_finished();