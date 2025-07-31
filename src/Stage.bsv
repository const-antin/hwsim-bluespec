import Vector::*;
import FIFO::*;
import Parameters::*;
import Types::*;
import Instructions::*;

interface StageFunction_IFC;
    method Action put_input(Integer input_idx, Tuple2#(Data, StopToken) msg);
    method ActionValue#(Tuple2#(Data, StopToken)) get_output(Integer output_idx);
endinterface

interface Stage_IFC;
    method Action set_config(StageConfig cfg);
    method Action put_input(Integer input_idx, ChannelMessage msg);
    method ActionValue#(ChannelMessage) get_output(Integer output_idx);
endinterface

module mkStage(Stage_IFC);
    Reg#(Maybe#(StageConfig)) cfg <- mkReg(tagged Invalid);

    Vector#(NUM_INPUTS_PER_STAGE, FIFO#(ChannelMessage)) input_fifos <- replicateM(mkFIFO);
    Vector#(NUM_OUTPUTS_PER_STAGE, FIFO#(ChannelMessage)) output_fifos <- replicateM(mkFIFO);

    rule do_stage if (cfg matches tagged Valid .cfg_unpacked);
        case (cfg_unpacked) matches
            tagged Map_t {.map_cfg}: begin

            end
            tagged Accumulate_t {.accumulate_cfg}: begin
            end
            tagged Broadcast_t {.broadcast_cfg}: begin
                let in = broadcast_cfg.inputs;

                case (input_fifos[in].first) matches
                    tagged Tag_EndToken .end_token: begin
                        cfg <= tagged Invalid;
                    end
                    default: begin end
                endcase
                
                for (Integer i = 0; i < valueOf(NUM_OUTPUTS_PER_STAGE); i = i + 1) begin
                    output_fifos[i].enq(input_fifos[in].first);
                end
                input_fifos[in].deq;
            end
            tagged Concat_t {.concat_cfg}: begin
            end
            tagged Enumerate_t {.enumerate_cfg}: begin
            end
            tagged Flatten_t {.flatten_cfg}: begin
            end
            tagged Flatmap_t {.flatmap_cfg}: begin
            end
            tagged RepeatN_t {.repeat_n_cfg}: begin
            end
            tagged RepeatRef_t {.repeat_ref_cfg}: begin
            end
            tagged RepeatStatic_t {.repeat_static_cfg}: begin
            end
            tagged Reshape_t {.reshape_cfg}: begin
            end
            tagged Reassemble_t {.reassemble_cfg}: begin
            end
            tagged Rotate_t {.rotate_cfg}: begin
            end
            tagged Parallelize_t {.parallelize_cfg}: begin
            end
            tagged Partition_t {.partition_cfg}: begin  
            end
            tagged Promote_t {.promote_cfg}: begin
            end
            tagged Scan_t {.scan_cfg}: begin
            end
            tagged SpatialMatmulT_t {.spatial_matmul_t_cfg}: begin
            end
            tagged SpatialMatmul_t {.spatial_matmul_cfg}: begin
            end
            default: begin
                $display("Invalid stage config");
            end
        endcase
    endrule

    method Action put_input(Integer input_idx, ChannelMessage msg);
        input_fifos[input_idx].enq(msg);
    endmethod

    method Action set_config(StageConfig config_in) if (cfg matches tagged Invalid);
        cfg <= tagged Valid config_in;
    endmethod

    method ActionValue#(ChannelMessage) get_output(Integer output_idx);
        let ret = output_fifos[output_idx].first;
        output_fifos[output_idx].deq;
        return ret;
    endmethod
endmodule