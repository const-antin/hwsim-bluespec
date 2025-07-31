package ReconfigurableInterconnect;

import Types::*;
import Vector::*;
import FIFO::*;
import Parameters::*;
import Instructions::*;
import RegFile::*;
import FIFOF::*;
import InstructionTable::*;
import StmtFSM::*;
import PCU::*;

// Interface for the reconfigurable interconnect
interface ReconfigurableInterconnect_IFC;
    method Action pcu_send_to_interconnect(Integer pcu_idx, Integer port_idx, ChannelMessage msg);
    method Action pcu_get_from_interconnect(Integer pcu_idx, Integer port_idx, ChannelMessage msg);

    method Action pmu_send_to_interconnect(Integer pmu_idx, Integer port_idx, ChannelMessage msg);
    method Action pmu_get_from_interconnect(Integer pmu_idx, Integer port_idx, ChannelMessage msg);

    method Action system_send_to_interconnect(Integer output_idx, ChannelMessage msg);
    method ActionValue#(ChannelMessage) system_get_from_interconnect(Integer output_idx);
endinterface

function UInt#(TLog#(NUM_CONNECTIONS_INTO_INTERCONNECT)) output_index_type_to_uint(GlobalPortIdx index);
    UInt#(TLog#(NUM_CONNECTIONS_INTO_INTERCONNECT)) ret = 0;
    case (index) matches
        tagged Tag_PCU_Port {.pcu_idx, .port_idx}: ret = (
            fromInteger(valueOf(NUM_SYSTEM_INPUTS)) + 
            fromInteger(valueOf(NUM_OUTPUTS_PER_PCU)) * unpack(extend(pack(pcu_idx))) + 
            unpack(extend(pack(port_idx))));
        tagged Tag_PMU_Port {.pmu_idx, .port_idx}: ret = (
            fromInteger(valueOf(NUM_SYSTEM_INPUTS)) + 
            fromInteger(valueOf(NUM_PCUS) * valueOf(NUM_OUTPUTS_PER_PCU)) + 
            fromInteger(valueOf(NUM_OUTPUTS_PER_PMU)) * unpack(extend(pack(pmu_idx))) + 
            unpack(extend(pack(port_idx))));
        tagged Tag_IO_Port .idx: ret = unpack(extend(pack(idx)));
    endcase
    return ret;
endfunction

function UInt#(TLog#(NUM_CONNECTIONS_OUT_OF_INTERCONNECT)) input_index_type_to_uint(GlobalPortIdx index);
    UInt#(TLog#(NUM_CONNECTIONS_OUT_OF_INTERCONNECT)) ret = 0;
    case (index) matches
        tagged Tag_PCU_Port {.pcu_idx, .port_idx}: ret = (
            fromInteger(valueOf(NUM_SYSTEM_OUTPUTS)) + 
            fromInteger(valueOf(NUM_INPUTS_PER_PCU)) * unpack(extend(pack(pcu_idx))) + 
            unpack(extend(pack(port_idx))));
        tagged Tag_PMU_Port {.pmu_idx, .port_idx}: ret = (
            fromInteger(valueOf(NUM_SYSTEM_OUTPUTS)) + 
            fromInteger(valueOf(NUM_PCUS) * valueOf(NUM_INPUTS_PER_PCU)) + 
            fromInteger(valueOf(NUM_INPUTS_PER_PMU)) * 
            unpack(extend(pack(pmu_idx))) + 
            unpack(extend(pack(port_idx))));
        tagged Tag_IO_Port .idx: ret = unpack(extend(pack(idx)));
    endcase
    return ret;
endfunction

module mkReconfigurableInterconnect#(InstructionTable_IFC instruction_table) (ReconfigurableInterconnect_IFC);
    Vector#(NUM_CONNECTIONS_INTO_INTERCONNECT, FIFO#(ChannelMessage)) into_interconnect <- replicateM(mkFIFO);
    Vector#(NUM_CONNECTIONS_OUT_OF_INTERCONNECT, FIFO#(ChannelMessage)) out_of_interconnect <- replicateM(mkFIFO);
    Vector#(NUM_CONNECTIONS_INTO_INTERCONNECT, Reg#(Maybe#(GlobalPortIdx))) io_mapping <- replicateM(mkReg(tagged Invalid));

    for (Integer i = 0; i < valueOf(NUM_CONNECTIONS_INTO_INTERCONNECT); i = i + 1) begin
        rule handle_into_interconnect;
            let msg = into_interconnect[i].first;
            into_interconnect[i].deq;
            $display("Handling into interconnect %d", i);
            case (msg) matches
                tagged Tag_Data {.data, .st}: begin
                    $display("Enqueuing data to out of interconnect %d", i);
                    if (io_mapping[i] matches tagged Valid .valid) begin
                        let idx = output_index_type_to_uint(valid);
                        out_of_interconnect[idx].enq(msg);
                    end else begin
                        $display("Error: Invalid IO mapping for into interconnect %d", i);
                        $finish(-1);
                    end
                end
                tagged Tag_Instruction .instruction_ptr: begin
                    $display("Received instruction %s", fshow(instruction_ptr));
                    let address <- instruction_table.get_alloc_component(instruction_ptr);
                    case (address) matches
                        tagged Tag_PCU .pcu_idx: begin
                            let new_address = tagged Tag_PCU_Port tuple2(pcu_idx, truncate(instruction_ptr.port_idx));
                            io_mapping[i] <= tagged Valid new_address;
                            let idx = output_index_type_to_uint(new_address);
                            $display("Allocated PCU %d at wire %d. Sending it %s", pcu_idx, idx, fshow(instruction_ptr));
                            out_of_interconnect[idx].enq(tagged Tag_Instruction instruction_ptr);
                        end 
                        tagged Tag_PMU .pmu_idx: begin
                            let new_address = tagged Tag_PMU_Port tuple2(pmu_idx, truncate(instruction_ptr.port_idx));
                            io_mapping[i] <= tagged Valid new_address;
                            let idx = output_index_type_to_uint(new_address);
                            $display("Allocated PMU %d at wire %d. Sending it %s", pmu_idx, idx, fshow(instruction_ptr));
                            out_of_interconnect[idx].enq(tagged Tag_Instruction instruction_ptr);
                        end 
                        tagged Tag_IO .idx: begin 
                            let new_address = tagged Tag_IO_Port idx;
                            io_mapping[i] <= tagged Valid new_address;
                            let idx = output_index_type_to_uint(new_address);
                            $display("Allocated IO %d at wire %d. Sending it %s", idx, idx, fshow(instruction_ptr));
                            out_of_interconnect[idx].enq(tagged Tag_Instruction instruction_ptr);
                        end
                    endcase
                end 
                tagged Tag_EndToken: begin
                    io_mapping[i] <= tagged Invalid;
                end
            endcase
        endrule

        rule idling;
            let idle = into_interconnect[i].first;
            $display("Interconnect %d is idling with message %s", i, fshow(idle));
        endrule 
    end

    method Action pcu_send_to_interconnect(Integer pcu_idx, Integer port_idx, ChannelMessage msg);
        let idx = output_index_type_to_uint(tagged Tag_PCU_Port tuple2(fromInteger(pcu_idx), fromInteger(port_idx)));
        into_interconnect[idx].enq(msg);
    endmethod 
    method Action pcu_get_from_interconnect(Integer pcu_idx, Integer port_idx, ChannelMessage msg);
        let idx = input_index_type_to_uint(tagged Tag_PCU_Port tuple2(fromInteger(pcu_idx), fromInteger(port_idx)));
        out_of_interconnect[idx].deq;
        msg = out_of_interconnect[idx].first;
    endmethod 

    method Action pmu_send_to_interconnect(Integer pmu_idx, Integer port_idx, ChannelMessage msg);
        let idx = output_index_type_to_uint(tagged Tag_PMU_Port tuple2(fromInteger(pmu_idx), fromInteger(port_idx)));
        into_interconnect[idx].enq(msg);
    endmethod

    method Action pmu_get_from_interconnect(Integer pmu_idx, Integer port_idx, ChannelMessage msg);
        let idx = input_index_type_to_uint(tagged Tag_PMU_Port tuple2(fromInteger(pmu_idx), fromInteger(port_idx)));
        out_of_interconnect[idx].deq;
        msg = out_of_interconnect[idx].first;
    endmethod

    method Action system_send_to_interconnect(Integer output_idx, ChannelMessage msg);
        let idx = output_index_type_to_uint(tagged Tag_IO_Port (fromInteger(output_idx)));
        into_interconnect[idx].enq(msg);
    endmethod
    
    method ActionValue#(ChannelMessage) system_get_from_interconnect(Integer output_idx);
        let idx = input_index_type_to_uint(tagged Tag_IO_Port (fromInteger(output_idx)));
        out_of_interconnect[idx].deq;
        return out_of_interconnect[idx].first;
    endmethod
endmodule

// Test module for the reconfigurable interconnect with instruction table
module mkReconfigurableInterconnectTest(Empty);
    InstructionTable_IFC instruction_table <- mkInstructionTable;
    ReconfigurableInterconnect_IFC interconnect <- mkReconfigurableInterconnect(instruction_table);

    // Generate a PCUInstruction with example fields
    PCUInstruction example_pcu_instruction = PCUInstruction {
        op: tagged Tag_RepeatStatic RepeatStaticConfig { count: 4 },
        input_ports: replicate(tagged Invalid),
        output_ports: replicate(tagged Invalid),
        debug_id: 123
    };

    let tile = 0;
    let data = tagged Tag_Tile tile;
    let stop_token = 1;
    let message = tagged Tag_Data (tuple2(data, stop_token));

    Reg#(Instruction_Ptr) instruction_ptr <- mkReg(?);
    Reg#(Instruction_Ptr) instruction_ptr_2 <- mkReg(?);

    PCUAndTargetConfig pcu_config = ?;

    mkAutoFSM(
        seq
            action
                let t <- instruction_table.add_pcu_instruction(example_pcu_instruction);
                instruction_ptr <= t;
                $display("Added instruction %d", t);
            endaction
            action
                let t <- instruction_table.add_pcu_instruction(example_pcu_instruction);
                instruction_ptr_2 <= t;
                $display("Added instruction %d", t);
            endaction
            action
                instruction_table.add_instruction_output(instruction_ptr, instruction_ptr_2);
                $display("Added instruction output");
            endaction
            action
                interconnect.system_send_to_interconnect(0, tagged Tag_Instruction instruction_ptr);
                $display("Sent instruction to system");
            endaction

            action
                interconnect.system_send_to_interconnect(0, message);
                $display("Sent data to system");
            endaction
            action 
                interconnect.pcu_get_from_interconnect(0, 0, message);
                $display("Received message for pcu: %s", fshow(message));
            endaction
            action
                interconnect.pcu_get_from_interconnect(0, 0, message);
                $display("Received message for pcu: %s", fshow(message));
            endaction
            action
                let msg <- interconnect.system_get_from_interconnect(0);
                $display("Received message from system: %s", fshow(msg));
            endaction
            action
                $display("Test completed successfully!");
                $finish(0);
            endaction
        endseq
    );
endmodule

endpackage 