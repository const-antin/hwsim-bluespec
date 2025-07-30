package InstructionTable;

import Types::*;
import Vector::*;
import FIFO::*;
import Parameters::*;
import Instructions::*;
import FIFOF::*;
import RegFile::*;
import StmtFSM::*;

// Instruction table interface
interface InstructionTable_IFC;
    // Add instructions
    method ActionValue#(Instruction_Ptr) add_pcu_instruction(PCUInstruction instruction);
    method ActionValue#(Instruction_Ptr) add_pmu_instruction(PMUInstruction instruction);
    
    // Add instruction output mappings
    method Action add_instruction_output(Instruction_Ptr instruction, PortIdx output_port_idx, 
                                       Instruction_Ptr target_instruction, PortIdx target_port_idx);
    
    // Get configurations
    method ActionValue#(PCUAndTargetConfig) get_pcu_config(Instruction_Ptr instruction);
    method ActionValue#(PMUAndTargetConfig) get_pmu_config(Instruction_Ptr instruction);
    
    // Component allocation
    method ActionValue#(Maybe#(Tuple2#(ComputeType, ComponentIdx))) get_alloc_component(Instruction_Ptr instruction);
    method Action free_pcu(Integer pcu_idx);
    method Action free_pmu(Integer pmu_idx);
    
    // Status queries
    method Bool has_free_pcu();
    method Bool has_free_pmu();
    method UInt#(TLog#(NUM_PCUS)) get_total_pcus();
    method UInt#(TLog#(NUM_PMUS)) get_total_pmus();
endinterface

module mkInstructionTable(InstructionTable_IFC);
    
    // Instruction storage
    RegFile#(InstructionIdx, Maybe#(PCUInstruction)) pcu_instructions <- mkRegFile(0, fromInteger(valueOf(NUM_PCU_INSTRUCTIONS)));
    RegFile#(InstructionIdx, Maybe#(PMUInstruction)) pmu_instructions <- mkRegFile(0, fromInteger(valueOf(NUM_PMU_INSTRUCTIONS)));
    RegFile#(InstructionIdx, ComponentTarget) pcu_targets <- mkRegFile(0, fromInteger(valueOf(NUM_PCU_INSTRUCTIONS)));
    RegFile#(InstructionIdx, ComponentTarget) pmu_targets <- mkRegFile(0, fromInteger(valueOf(NUM_PMU_INSTRUCTIONS)));

    // Next instruction mappings
    Vector#(NUM_PCUS, Vector#(NUM_OUTPUTS_PER_PCU, Reg#(Maybe#(Tuple2#(Instruction_Ptr, PortIdx))))) 
        next_instructions <- replicateM(replicateM(mkReg(Invalid)));
    
    // Component allocations
    Reg#(Vector#(NUM_PCUS, Maybe#(Instruction_Ptr))) pcu_allocation <- mkReg(replicate(Invalid));
    Reg#(Vector#(NUM_PMUS, Maybe#(Instruction_Ptr))) pmu_allocation <- mkReg(replicate(Invalid));
    
    // Instruction counter
    Reg#(InstructionIdx) pcu_instruction_ctr <- mkReg(0);
    Reg#(InstructionIdx) pmu_instruction_ctr <- mkReg(0);
    
    function Maybe#(ComponentIdx) find_free_pcu() = findIndex(isValid, pcu_allocation);
    function Maybe#(ComponentIdx) find_free_pmu() = findIndex(isValid, pmu_allocation);
    
    function Bool free_pred(Instruction_Ptr test, Maybe#(Instruction_Ptr) instruction);
        let found = False;
        if (instruction matches tagged Valid .instr &&& instr == test)
            found = True;
        return found;
    endfunction

    // Add PCU instruction
    method ActionValue#(Instruction_Ptr) add_pcu_instruction(PCUInstruction instruction);
        pcu_instruction_ctr <= pcu_instruction_ctr + 1;
        pcu_instructions.upd(pcu_instruction_ctr, tagged Valid instruction);
        pcu_targets.upd(pcu_instruction_ctr, ComponentTarget {
            port_mappings: replicate(tagged Invalid)
        });
        return Instruction_Ptr {
            instruction_idx: pcu_instruction_ctr,
            compute_type: ComputeType_PCU
        };
    endmethod
    
    // Add PMU instruction
    method ActionValue#(Instruction_Ptr) add_pmu_instruction(PMUInstruction instruction);
        pmu_instruction_ctr <= pmu_instruction_ctr + 1;
        pmu_instructions.upd(pmu_instruction_ctr, tagged Valid instruction);
        pmu_targets.upd(pmu_instruction_ctr, ComponentTarget {
            port_mappings: replicate(tagged Invalid)
        });
        return Instruction_Ptr {
            instruction_idx: pmu_instruction_ctr,
            compute_type: ComputeType_PMU
        };
    endmethod
    
    // Add instruction output mapping
    method Action add_instruction_output(Instruction_Ptr instruction, PortIdx output_port_idx, 
                                       Instruction_Ptr target_instruction, PortIdx target_port_idx);
        if (instruction.compute_type == ComputeType_PCU) begin
            let entry = pcu_targets.sub(instruction.instruction_idx);
            entry.port_mappings[output_port_idx] = tagged Valid tuple2(target_instruction, target_port_idx);
            pcu_targets.upd(instruction.instruction_idx, entry);
        end else if (instruction.compute_type == ComputeType_PMU) begin
            let entry = pmu_targets.sub(instruction.instruction_idx);
            entry.port_mappings[output_port_idx] = tagged Valid tuple2(target_instruction, target_port_idx);
            pmu_targets.upd(instruction.instruction_idx, entry);
        end else begin
            $display("Error: Invalid compute type %d", instruction.compute_type);
            $finish(-1);
        end
    endmethod
    
    // Get PCU configuration
    method ActionValue#(PCUAndTargetConfig) get_pcu_config(Instruction_Ptr instruction);
        // Find the PCU with this instruction
        let instruction_config = pcu_instructions.sub(instruction.instruction_idx);
        if (instruction_config matches tagged Invalid) begin
            $display("Error: PCU instruction %d not in instruction table", instruction);
            $finish(-1);
        end
        let target = pcu_targets.sub(instruction.instruction_idx);
        return PCUAndTargetConfig {
            pcu_config: instruction_config.Valid,
            target: target
        };
    endmethod
    
    // Get PMU configuration
    method ActionValue#(PMUAndTargetConfig) get_pmu_config(Instruction_Ptr instruction);
        // Find the PMU with this instruction
        let instruction_config = pmu_instructions.sub(instruction.instruction_idx);
        if (instruction_config matches tagged Invalid) begin
            $display("Error: PMU instruction %d not in instruction table", instruction);
            $finish(-1);
        end
        let target = pmu_targets.sub(instruction.instruction_idx);
        return PMUAndTargetConfig {
            pmu_config: instruction_config.Valid,
            target: target
        };
    endmethod
    
    // Get allocated component
    method ActionValue#(Maybe#(Tuple2#(ComputeType, ComponentIdx))) get_alloc_component(Instruction_Ptr instruction);
        Maybe#(Tuple2#(ComputeType, ComponentIdx)) ret = tagged Invalid;

        if (instruction.compute_type == ComputeType_Output) begin
            ret = tagged Valid tuple2(ComputeType_Output, 0);
        end
        
        // Check PCU allocations
        else if (findIndex(free_pred(instruction), pcu_allocation) matches tagged Valid .idx) begin
            ret = tagged Valid tuple2(ComputeType_PCU, idx);
        end
        else if (findIndex(free_pred(instruction), pmu_allocation) matches tagged Valid .idx) begin
            ret = tagged Valid tuple2(ComputeType_PMU, idx);
        end
        
        // Try to allocate a new PCU
        else if (find_free_pcu() matches tagged Valid .pcu_idx) begin
            ret = tagged Valid tuple2(ComputeType_PCU, pcu_idx);
        end
        
        // Try to allocate a new PMU
        else if (find_free_pmu() matches tagged Valid .pmu_idx) begin
            ret = tagged Valid tuple2(ComputeType_PMU, pmu_idx);
        end
        else begin
            ret = tagged Invalid;
        end 
        return ret;
    endmethod

    // Free PCU
    method Action free_pcu(Integer pcu_idx);
        if (pcu_allocation[pcu_idx] matches tagged Valid .instruction) begin
            pcu_allocation[pcu_idx] <= tagged Invalid;
            $display("Freed PCU %d for instruction %d", pcu_idx, instruction);
        end else begin
            $display("Error: Failed to free PCU for id %d", pcu_idx);
            $finish(-1);
        end
    endmethod
    
    // Free PMU
    method Action free_pmu(Integer pmu_idx);
        if (pmu_allocation[pmu_idx] matches tagged Valid .instruction) begin
            pmu_allocation[pmu_idx] <= tagged Invalid;
            $display("Freed PMU %d for instruction %d", pmu_idx, pmu_allocation[pmu_idx].Valid);
        end else begin
            $display("Error: Failed to free PMU for id %d", pmu_idx);
            $finish(-1);
        end
    endmethod
    
    // Status queries
    method Bool has_free_pcu();
        return isValid(find_free_pcu());
    endmethod
    
    method Bool has_free_pmu();
        return isValid(find_free_pmu());
    endmethod
    
    method UInt#(TLog#(NUM_PCUS)) get_total_pcus();
        return fromInteger(valueOf(NUM_PCUS));
    endmethod
    
    method UInt#(TLog#(NUM_PMUS)) get_total_pmus();
        return fromInteger(valueOf(NUM_PMUS));
    endmethod
    
endmodule

module mkInstructionTableTest(Empty);

    InstructionTable_IFC instruction_table <- mkInstructionTable;

    Reg#(Instruction_Ptr) pcu_instruction_idx <- mkRegU;
    Reg#(Instruction_Ptr) pmu_instruction_idx <- mkRegU;

    mkAutoFSM(
        seq
            action 
                let pcu_instruction <- instruction_table.add_pcu_instruction(PCUInstruction {
                    op: tagged Tag_RepeatStatic RepeatStaticConfig {count: 2},
                    input_ports: replicate(tagged Invalid),
                    output_ports: replicate(tagged Invalid),
                    debug_id: 1
                });
                pcu_instruction_idx <= pcu_instruction;
            endaction
            action
                instruction_table.add_instruction_output(pcu_instruction_idx, 0, pcu_instruction_idx, 0);
            endaction 
            action
                let pmu_instruction <- instruction_table.add_pmu_instruction(PMUInstruction {});
                pmu_instruction_idx <= pmu_instruction;
            endaction
            action
                let pcu_config <- instruction_table.get_pcu_config(pcu_instruction_idx);
                $display("PCU config: %s", fshow(pcu_config));
            endaction
            action
                let pmu_config <- instruction_table.get_pmu_config(pmu_instruction_idx);
                $display("PMU config: %s", fshow(pmu_config));
            endaction
        endseq
    );
endmodule
endpackage 