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
    method Action add_instruction_output(Instruction_Ptr instruction, 
                                       Instruction_Ptr target_instruction);
    
    // Get configurations
    method ActionValue#(PCUAndTargetConfig) get_pcu_config(InstructionIdx instruction_idx);
    method ActionValue#(PMUAndTargetConfig) get_pmu_config(InstructionIdx instruction_idx);
    
    // Component allocation
    method ActionValue#(GlobalComponentIdx) get_alloc_component(Instruction_Ptr instruction);
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
    
    function isInvalid(m) = !isValid(m);
    function Maybe#(ComponentIdx) find_free_pcu() = findIndex(isInvalid, pcu_allocation);
    function Maybe#(ComponentIdx) find_free_pmu() = findIndex(isInvalid, pmu_allocation);
    
    function Bool allocated_pred(Instruction_Ptr test, Maybe#(Instruction_Ptr) instruction);
        let found = False;
        if (instruction matches tagged Valid .instr &&& instr.instruction_idx == test.instruction_idx &&& instr.compute_type == test.compute_type)
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
    method Action add_instruction_output(Instruction_Ptr instruction, 
                                       Instruction_Ptr target_instruction);
        if (instruction.compute_type == ComputeType_PCU) begin
            let entry = pcu_targets.sub(instruction.instruction_idx);
            entry.port_mappings[instruction.port_idx] = tagged Valid target_instruction;
            pcu_targets.upd(instruction.instruction_idx, entry);
        end else if (instruction.compute_type == ComputeType_PMU) begin
            let entry = pmu_targets.sub(instruction.instruction_idx);
            entry.port_mappings[instruction.port_idx] = tagged Valid target_instruction;
            pmu_targets.upd(instruction.instruction_idx, entry);
        end else begin
            $display("Error: Invalid compute type %d", instruction.compute_type);
            $finish(-1);
        end
    endmethod
    
    // Get PCU configuration
    method ActionValue#(PCUAndTargetConfig) get_pcu_config(InstructionIdx instruction_idx);
        // Find the PCU with this instruction
        let instruction_config = pcu_instructions.sub(instruction_idx);
        if (instruction_config matches tagged Invalid) begin
            $display("Error: PCU instruction %d not in instruction table", instruction_idx);
            $finish(-1);
        end
        let target = pcu_targets.sub(instruction_idx);
        return PCUAndTargetConfig {
            pcu_config: instruction_config.Valid,
            target: target
        };
    endmethod
    
    // Get PMU configuration
    method ActionValue#(PMUAndTargetConfig) get_pmu_config(InstructionIdx instruction_idx);
        // Find the PMU with this instruction
        let instruction_config = pmu_instructions.sub(instruction_idx);
        if (instruction_config matches tagged Invalid) begin
            $display("Error: PMU instruction %d not in instruction table", instruction_idx);
            $finish(-1);
        end
        let target = pmu_targets.sub(instruction_idx);
        return PMUAndTargetConfig {
            pmu_config: instruction_config.Valid,
            target: target
        };
    endmethod
    
    // Get allocated component
    method ActionValue#(GlobalComponentIdx) get_alloc_component(Instruction_Ptr instruction);
        GlobalComponentIdx ret = tagged Tag_IO 0; // Default initialization

        // Handle io instructions
        if (instruction.compute_type == ComputeType_Output) begin
            ret = tagged Tag_IO instruction.port_idx;
        end
        
        // Handle PCU instructions
        else if (instruction.compute_type == ComputeType_PCU) begin
            if (findIndex(allocated_pred(instruction), pcu_allocation) matches tagged Valid .idx) begin
                ret = tagged Tag_PCU idx;
            end else if (find_free_pcu() matches tagged Valid .pcu_idx) begin
                ret = tagged Tag_PCU pcu_idx;
                pcu_allocation[pcu_idx] <= tagged Valid instruction;
            end else begin
                $display("Error: Failed to allocate PCU for instruction %s", fshow(instruction));
                $finish(-1);
            end
        end
        
        // Handle PMU instructions
        else if (instruction.compute_type == ComputeType_PMU) begin
            if (findIndex(allocated_pred(instruction), pmu_allocation) matches tagged Valid .idx) begin
                ret = tagged Tag_PMU idx;
            end else if (find_free_pmu() matches tagged Valid .pmu_idx) begin
                ret = tagged Tag_PMU pmu_idx;
                pmu_allocation[pmu_idx] <= tagged Valid instruction;
            end else begin
                $display("Error: Failed to allocate PMU for instruction %s", fshow(instruction));
                $finish(-1);
            end
        end
        else begin
            $display("Error: Failed to allocate component for instruction %s", fshow(instruction));
            $finish(-1);
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
                instruction_table.add_instruction_output(pcu_instruction_idx, pcu_instruction_idx);
            endaction 
            action
                let pmu_instruction <- instruction_table.add_pmu_instruction(PMUInstruction {});
                pmu_instruction_idx <= pmu_instruction;
            endaction
            action
                let pcu_config <- instruction_table.get_pcu_config(pcu_instruction_idx.instruction_idx);
                $display("PCU config: %s", fshow(pcu_config));
            endaction
            action
                let pmu_config <- instruction_table.get_pmu_config(pmu_instruction_idx.instruction_idx);
                $display("PMU config: %s", fshow(pmu_config));
            endaction
        endseq
    );
endmodule
endpackage 