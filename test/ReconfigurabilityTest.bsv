import Parameters::*;
import PCU::*;
import InstructionTable::*;
import ReconfigurableInterconnect::*;
import Types::*;
import Vector::*;
import Instructions::*;
import StmtFSM::*;

module mkReconfigurabilityTest(Empty);

    Vector#(NUM_PCUS, PCU_IFC) pcus <- replicateM(mkPCU);
    
    InstructionTable_IFC instruction_table <- mkInstructionTable;
    ReconfigurableInterconnect_IFC interconnect <- mkReconfigurableInterconnect(instruction_table);
    Reg#(Int#(32)) cycle <- mkReg(0);

    Tuple2#(Data, StopToken) zero_tile = tuple2(tagged Tag_Tile 0, 0);
    Tuple2#(Data, StopToken) one_tile = tuple2(tagged Tag_Tile 1, 0);
    Tuple2#(Data, StopToken) two_tile = tuple2(tagged Tag_Tile 2, 0);

    Vector#(NUM_INPUTS_PER_PCU, Maybe#(UInt#(TLog#(NUM_INPUTS_PER_PCU)))) input_select_1 = append(
        cons(tagged Valid 0, nil),
        replicate(tagged Invalid));
    Vector#(NUM_INPUTS_PER_PCU, Maybe#(UInt#(TLog#(NUM_INPUTS_PER_PCU)))) input_select_2 = append(
        cons(tagged Valid 0, cons(tagged Valid 1, nil)),
        replicate(tagged Invalid));
    Vector#(NUM_OUTPUTS_PER_PCU, Maybe#(UInt#(TLog#(NUM_OUTPUTS_PER_PCU)))) output_select_1 = append(
        cons(tagged Valid 0, nil),
        replicate(tagged Invalid));
    
    PCUInstruction add_instruction = PCUInstruction {
        op: tagged Tag_BinaryMap BinaryMapConfig {op: ADD},
        input_ports: input_select_2,
        output_ports: output_select_1,
        debug_id: 0
    };

    PCUInstruction repeat_static_instruction = PCUInstruction {
        op: tagged Tag_RepeatStatic RepeatStaticConfig {count: 2},
        input_ports: input_select_1,
        output_ports: output_select_1,
        debug_id: 1
    };

    Instruction_Ptr output_ptr = Instruction_Ptr {
        instruction_idx: 0,
        compute_type: ComputeType_Output,
        port_idx: 0
    };

    Reg#(Instruction_Ptr) instruction_ptr <- mkReg(?);
    Reg#(Instruction_Ptr) instruction_ptr_2 <- mkReg(?);

    mkAutoFSM(
        par
            seq // Cycle Counter 
                while (True)
                    action
                        cycle <= cycle + 1;
                    endaction
            endseq 

            seq // Populate Instruction Table && Send Test Data
                action 
                    let t <- instruction_table.add_pcu_instruction(add_instruction); // TODO: This here should not return an instruction with port_idx, but it currently does. It should return just the instruction_idx of the PCUInstruction, and give the user the task to augment the instruction_ptr with the port_idx.
                    instruction_ptr <= t;
                    $display("Added instruction %s", fshow(t));
                endaction 
                action 
                    let t <- instruction_table.add_pcu_instruction(repeat_static_instruction);
                    instruction_ptr_2 <= t;
                    $display("Added instruction %s", fshow(t));
                endaction 
                action
                    let ptr = instruction_ptr;
                    ptr.port_idx = 0;
                    let ptr_2 = instruction_ptr_2;
                    ptr_2.port_idx = 0;
                    instruction_table.add_instruction_output(ptr, ptr_2);
                    $display("Added instruction output");
                endaction 
                action 
                    let ptr_2 = instruction_ptr_2;
                    ptr_2.port_idx = 0;
                    instruction_table.add_instruction_output(ptr_2, output_ptr);
                    $display("Added instruction output");
                endaction 
                action 
                    let ptr = instruction_ptr;
                    ptr.port_idx = 0;
                    interconnect.system_send_to_interconnect(0, tagged Tag_Instruction ptr);
                    ptr.port_idx = 1;
                    interconnect.system_send_to_interconnect(1, tagged Tag_Instruction ptr);
                    $display("Sent instruction to system");
                endaction 
                action
                    interconnect.system_send_to_interconnect(0, tagged Tag_Data zero_tile);
                    interconnect.system_send_to_interconnect(1, tagged Tag_Data one_tile);
                    $display("Sent data to system");
                endaction 
                action
                    interconnect.system_send_to_interconnect(0, tagged Tag_Data one_tile);
                    interconnect.system_send_to_interconnect(1, tagged Tag_Data two_tile);
                    $display("Sent data to system");
                endaction 
                action
                    interconnect.system_send_to_interconnect(0, tagged Tag_EndToken);
                    interconnect.system_send_to_interconnect(1, tagged Tag_EndToken);
                    $display("Sent end token to system");
                endaction
            endseq

            seq // Drain reference data
                while (True)
                    action // Should be instruction
                        let t <- interconnect.system_get_from_interconnect(0);
                        $display("Received message from system: %s", fshow(t));
                        if (t matches tagged Tag_EndToken) begin
                            $finish(0);
                        end
                    endaction
            endseq 

            seq // Data from Interconnect -> PCU
                while (True)
                    action
                        let t <- interconnect.pcu_get_from_interconnect(0, 0);
                        pcus[0].put(0, t);
                        $display("Moving from Interconnect to PCU 0, Port 0: %s", fshow(t));
                    endaction
            endseq

            seq 
                while (True) 
                    action 
                        let t <- interconnect.pcu_get_from_interconnect(0, 1);
                        pcus[0].put(1, t);
                        $display("Moving from Interconnect to PCU 0, Port 1: %s", fshow(t));
                    endaction
            endseq 

            seq
                while (True)  
                    action
                        let t <- interconnect.pcu_get_from_interconnect(1, 0);
                        pcus[1].put(0, t);
                        $display("Moving from Interconnect to PCU 1, Port 0: %s", fshow(t));
                    endaction
            endseq 

            seq // Data from PCU -> Interconnect
                while (True) 
                    action
                        let t <- pcus[0].get(0);
                        interconnect.pcu_send_to_interconnect(0, 0, t);
                        $display("Moving from PCU 0, Port 0 to Interconnect: %s", fshow(t));
                    endaction
            endseq

            seq 
                while (True) 
                    action
                        let t <- pcus[1].get(0);
                        interconnect.pcu_send_to_interconnect(1, 0, t);
                        $display("Moving from PCU 1, Port 0 to Interconnect: %s", fshow(t));
                    endaction
            endseq 

            seq
                while (True)
                    action 
                        let t <- pcus[0].get_instruction_request();
                        $display("Received instruction request: %s", fshow(t));
                        let instruction <- instruction_table.get_pcu_config(t);
                        $display("Putting instruction: %s", fshow(instruction));
                        pcus[0].put_instruction(instruction);
                    endaction 
            endseq 

            seq
                while (True)
                    action 
                        let t <- pcus[1].get_instruction_request();
                        $display("Received instruction request: %s", fshow(t));
                        let instruction <- instruction_table.get_pcu_config(t);
                        $display("Putting instruction: %s", fshow(instruction));
                        pcus[1].put_instruction(instruction);
                    endaction 
            endseq 
        endpar
    );
endmodule