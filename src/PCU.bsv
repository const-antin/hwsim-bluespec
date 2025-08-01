import Types::*;
import Vector::*;
import FIFO::*;
import Parameters::*;
import Instructions::*;
import Operation::*;
import ALU::*;
import StmtFSM::*;

interface PCU_IFC;
    method Action put_instruction(PCUAndTargetConfig instruction);
    method ActionValue#(InstructionIdx) get_instruction_request();
    method ActionValue#(ChannelMessage) get(Integer port);
    method Action put(Integer port, ChannelMessage msg);
    method Action done(); // get next done ack
endinterface

typedef union tagged {
    void Tag_Idle;
    InstructionIdx Tag_Requesting_Config;
    InstructionIdx Tag_Waiting_For_Config;
    Tuple2#(InstructionIdx, PCUAndTargetConfig) Tag_Computing;
} PCUState deriving (Bits, Eq, FShow);

module mkPCU(PCU_IFC);
    Vector#(NUM_INPUTS_PER_PCU, FIFO#(ChannelMessage)) submodule_inputs <- replicateM(mkFIFO);
    Vector#(NUM_OUTPUTS_PER_PCU, FIFO#(ChannelMessage)) submodule_outputs <- replicateM(mkFIFO);

    ALU_IFC alu <- mkALU;
    Accum_IFC accum <- mkAccum(submodule_outputs[0], alu);
    RepeatStatic_IFC repeat_static <- mkRepeatStatic(submodule_outputs[0]);
    UnaryMap_IFC unary_map <- mkUnaryMap(submodule_outputs[0], alu);
    BinaryMap_IFC binary_map <- mkBinaryMap(submodule_outputs[0], alu);
    Promote_IFC promote <- mkPromote(submodule_outputs[0]);
    AccumBigTile_IFC accum_big_tile <- mkAccumBigTile(submodule_outputs[0], submodule_outputs[1], alu);
    
    // Stub modules for missing operations
    Broadcast_IFC broadcast <- mkBroadcast(submodule_outputs[0], submodule_outputs[1]);
    Concat_IFC concat <- mkConcat(submodule_outputs[0]);
    Enumerate_IFC enumerate <- mkEnumerate(submodule_outputs[0], submodule_outputs[1]);
    Flatten_IFC flatten <- mkFlatten(submodule_outputs[0]);
    FlatMap_IFC flatmap <- mkFlatMap(submodule_outputs[0]);
    RepeatN_IFC repeat_n <- mkRepeatN(submodule_outputs[0]);
    RepeatRef_IFC repeat_ref <- mkRepeatRef(submodule_outputs[0]);
    Reshape_IFC reshape <- mkReshape(submodule_outputs[0]);
    Reassemble_IFC reassemble <- mkReassemble(submodule_outputs[0]);
    Rotate_IFC rotate <- mkRotate(submodule_outputs[0], submodule_outputs[1]);
    Parallelize_IFC parallelize <- mkParallelize(submodule_outputs[0], submodule_outputs[1]);
    Partition_IFC partition <- mkPartition(submodule_outputs[0], submodule_outputs[1]);
    Scan_IFC scan <- mkScan(submodule_outputs[0]);
    SpatialMatmulT_IFC spatial_matmul_t <- mkSpatialMatmulT(submodule_outputs[0], submodule_outputs[1], submodule_outputs[2]);

    Vector#(NUM_INPUTS_PER_PCU, FIFO#(ChannelMessage)) inputs <- replicateM(mkFIFO);
    Vector#(NUM_OUTPUTS_PER_PCU, FIFO#(ChannelMessage)) external_outputs <- replicateM(mkFIFO);

    Reg#(PCUState) state <- mkReg(tagged Tag_Idle);
    Reg#(Vector#(NUM_INPUTS_PER_PCU, Bool)) done_inputs <- mkReg(replicate(False));
    Reg#(Vector#(NUM_OUTPUTS_PER_PCU, Bool)) done_outputs <- mkReg(replicate(False));

    FIFO#(InstructionIdx) instruction_request <- mkFIFO;
    FIFO#(PCUAndTargetConfig) instruction_response <- mkFIFO;

    // Configure the PCU to the next instruction
    for (Integer i = 0; i < fromInteger(valueOf(NUM_INPUTS_PER_PCU)); i = i + 1) begin

        rule configure_first if (inputs[i].first matches tagged Tag_Instruction .instruction_ptr &&& state matches tagged Tag_Idle);
            // $display("Idle to Requesting Config");
            state <= tagged Tag_Requesting_Config instruction_ptr.instruction_idx;
            inputs[i].deq;
        endrule

        rule swallow_configs_while_requesting if (inputs[i].first matches tagged Tag_Instruction .incoming_instruction_ptr &&& state matches tagged Tag_Requesting_Config .instruction_idx &&& incoming_instruction_ptr.instruction_idx == instruction_idx);
            // $display("Swallowing redundant instruction");
            inputs[i].deq;
        endrule

        rule swallow_configs_while_waiting if (inputs[i].first matches tagged Tag_Instruction .incoming_instruction_ptr &&& state matches tagged Tag_Waiting_For_Config .instruction_idx &&& incoming_instruction_ptr.instruction_idx == instruction_idx);    
            // $display("Swallowing redundant instruction");
            inputs[i].deq;
        endrule

        rule swallow_configs_while_computing if (inputs[i].first matches tagged Tag_Instruction .incoming_instruction_ptr &&& state matches tagged Tag_Computing {.instruction_idx, .instruction} &&& incoming_instruction_ptr.instruction_idx == instruction_idx);
            // $display("Swallowing redundant instruction");
            inputs[i].deq;
        endrule
    end

    rule request_config if (state matches tagged Tag_Requesting_Config .instruction_idx);
        // $display("Requesting Config");
        instruction_request.enq(instruction_idx);
        state <= tagged Tag_Waiting_For_Config instruction_idx;
    endrule

    rule program_config if (state matches tagged Tag_Waiting_For_Config .instruction_idx);
        // $display("Waiting for config -> Tag_computing");
        let instruction = instruction_response.first.pcu_config;
        instruction_response.deq;
        state <= tagged Tag_Computing tuple2(instruction_idx, instruction_response.first);

        case (instruction.op) matches
            tagged Tag_UnaryMap .unary_map_inst:
                begin
                    unary_map.set_cfg(unary_map_inst);
                end

            tagged Tag_BinaryMap .binary_map_inst:
                begin
                    binary_map.set_cfg(binary_map_inst);
                end

            tagged Tag_AccumulateBigTile .acc_big_tile_inst:
                begin
                    accum_big_tile.set_cfg(acc_big_tile_inst);
                end

            tagged Tag_Accumulate .accumulate_inst:
                begin
                    accum.set_cfg(accumulate_inst);
                end

            tagged Tag_RepeatStatic .repeat_static_inst:
                begin
                    repeat_static.set_cfg(repeat_static_inst);
                end

            tagged Tag_Promote .promote_inst:
                begin
                    promote.set_cfg(promote_inst);
                end

            tagged Tag_Broadcast .broadcast_inst:
                begin
                    broadcast.set_cfg(broadcast_inst);
                end

            tagged Tag_Concat .concat_inst:
                begin
                    concat.set_cfg(concat_inst);
                end

            tagged Tag_Enumerate .enumerate_inst:
                begin
                    enumerate.set_cfg(enumerate_inst);
                end

            tagged Tag_Flatten .flatten_inst:
                begin
                    flatten.set_cfg(flatten_inst);
                end

            tagged Tag_FlatMap .flatmap_inst:
                begin
                    flatmap.set_cfg(flatmap_inst);
                end

            tagged Tag_RepeatN .repeat_n_inst:
                begin
                    repeat_n.set_cfg(repeat_n_inst);
                end

            tagged Tag_RepeatRef .repeat_ref_inst:
                begin
                    repeat_ref.set_cfg(repeat_ref_inst);
                end

            tagged Tag_Reshape .reshape_inst:
                begin
                    reshape.set_cfg(reshape_inst);
                end

            tagged Tag_Reassemble .reassemble_inst:
                begin
                    reassemble.set_cfg(reassemble_inst);
                end

            tagged Tag_Rotate .rotate_inst:
                begin
                    rotate.set_cfg(rotate_inst);
                end

            tagged Tag_Parallelize .parallelize_inst:
                begin
                    parallelize.set_cfg(parallelize_inst);
                end

            tagged Tag_Partition .partition_inst:
                begin
                    partition.set_cfg(partition_inst);
                end

            tagged Tag_Scan .scan_inst:
                begin
                    scan.set_cfg(scan_inst);
                end

            tagged Tag_SpatialMatmulT .spatial_matmul_t_inst:
                begin
                    spatial_matmul_t.set_cfg(spatial_matmul_t_inst);
                end
        endcase

        let port_mappings = instruction_response.first.target.port_mappings;
        for (Integer i = 0; i < fromInteger(valueOf(NUM_INPUTS_PER_PCU)); i = i + 1) begin
            if (port_mappings[i] matches tagged Valid .port_mapping) begin
                $display("Enqueuing instruction %s to output %d", fshow(port_mapping), i);
                external_outputs[i].enq(tagged Tag_Instruction port_mapping);
            end
        end
    endrule

    // Transition: Configuring -> Idle
    rule config_to_idle if (state matches tagged Tag_Computing {.instruction_idx, .instruction} &&& map(isValid, instruction.pcu_config.input_ports) == done_inputs &&& map(isValid, instruction.pcu_config.output_ports) == done_outputs);
        // $display("Configuring to Idle because selected inputs is %s and done inputs is %s and selected outputs is %s and done outputs is %s", fshow(map(isValid, instruction.input_ports)), fshow(done_inputs), fshow(map(isValid, instruction.output_ports)), fshow(done_outputs));
        
        // For each output, if done_outputs[i] is True, enqueue an end token
        for (Integer i = 0; i < fromInteger(valueOf(NUM_OUTPUTS_PER_PCU)); i = i + 1) begin
            if (done_outputs[i]) begin
                external_outputs[i].enq(tagged Tag_EndToken);
            end
        end

        state <= tagged Tag_Idle;
        done_inputs <= replicate(False);
        done_outputs <= replicate(False);
    endrule

    // Handle input to compute unit while being configured
    for (Integer i = 0; i < fromInteger(valueOf(NUM_INPUTS_PER_PCU)); i = i + 1) begin
        rule handle_compute_input if (
            state matches tagged Tag_Computing {.instruction_idx, .instruction} &&& 
            instruction.pcu_config.input_ports[i] matches tagged Valid .in_idx &&&
            !done_inputs[in_idx]);

            InstructionOp op = instruction.pcu_config.op;
            let in = inputs[in_idx].first;
            inputs[in_idx].deq;
            // $display("Handling compute input idx: %d, in_idx: %d, in: %s", i, in_idx, fshow(in));
            UInt#(32) idx = fromInteger(i);
            case (op) matches
                tagged Tag_Accumulate .accumulate_inst: begin
                    accum.op.put(idx, in);
                end
                tagged Tag_RepeatStatic .repeat_static_inst: begin
                    repeat_static.op.put(idx, in);
                end
                tagged Tag_UnaryMap .unary_map_inst: begin
                    unary_map.op.put(idx, in);
                end
                tagged Tag_BinaryMap .binary_map_inst: begin
                    binary_map.op.put(idx, in);
                end
                tagged Tag_Promote .promote_inst: begin
                    promote.op.put(idx, in);
                end
                tagged Tag_AccumulateBigTile .acc_big_tile_inst: begin
                    accum_big_tile.op.put(idx, in);
                end
                tagged Tag_Broadcast .broadcast_inst: begin
                    broadcast.op.put(idx, in);
                end
                tagged Tag_Concat .concat_inst: begin
                    concat.op.put(idx, in);
                end
                tagged Tag_Enumerate .enumerate_inst: begin
                    enumerate.op.put(idx, in);
                end
                tagged Tag_Flatten .flatten_inst: begin
                    flatten.op.put(idx, in);
                end
                tagged Tag_FlatMap .flatmap_inst: begin
                    flatmap.op.put(idx, in);
                end
                tagged Tag_RepeatN .repeat_n_inst: begin
                    repeat_n.op.put(idx, in);
                end
                tagged Tag_RepeatRef .repeat_ref_inst: begin
                    repeat_ref.op.put(idx, in);
                end
                tagged Tag_Reshape .reshape_inst: begin
                    reshape.op.put(idx, in);
                end
                tagged Tag_Reassemble .reassemble_inst: begin
                    reassemble.op.put(idx, in);
                end
                tagged Tag_Rotate .rotate_inst: begin
                    rotate.op.put(idx, in);
                end
                tagged Tag_Parallelize .parallelize_inst: begin
                    parallelize.op.put(idx, in);
                end
                tagged Tag_Partition .partition_inst: begin
                    partition.op.put(idx, in);
                end
                tagged Tag_Scan .scan_inst: begin
                    scan.op.put(idx, in);
                end
                tagged Tag_SpatialMatmulT .spatial_matmul_t_inst: begin
                    spatial_matmul_t.op.put(idx, in);
                end
                default:
                    $error("Unsupported operation in PCU");
            endcase

            if (in matches tagged Tag_EndToken) begin
                // $display("Setting done_inputs[%d] to True", i);
                done_inputs[i] <= True;
            end
        endrule
        // rule or_else;
        //     $display("State: %s", fshow(state));
        //     $display("Input[%d]: %s", i, fshow(inputs[i].first));
        //     $display("Inputs: %s", fshow(instruction.input_ports));
        //     $display("Outputs: %s", fshow(instruction.output_ports));
        //     $display("Done inputs: %s", fshow(done_inputs));
        // endrule 

    end

    for (Integer j = 0; j < fromInteger(valueOf(NUM_OUTPUTS_PER_PCU)); j = j + 1) begin
        rule drain_output if (state matches tagged Tag_Computing {.instruction_idx, .instruction} &&& instruction.pcu_config.output_ports[j] matches tagged Valid .out_idx);
            let out = submodule_outputs[j].first;
            submodule_outputs[j].deq;
            external_outputs[out_idx].enq(out);

            if (out matches tagged Tag_EndToken) begin
                done_outputs[j] <= True;
                // $display("Setting done_outputs[%d] to True", j);
            end
        endrule
    end

    // rule state_is_tag_computing;
    //     if (state matches tagged Tag_Computing .instruction) begin
    //         $display("State is Tag_Computing");
    //         $display("Input[%d]: %s", 0, fshow(inputs[0].first));
    //         $display("Inputs: %s", fshow(instruction.input_ports));
    //     end
    // endrule

    // rule config_not_to_idle if (state matches tagged Tag_Computing {.ptr, .instruction} &&& map(isValid, instruction.input_ports) == done_inputs &&& map(isValid, instruction.output_ports) == done_outputs);
    //     $display("Inputs done: %s and selected_inputs: %s", fshow(done_inputs), fshow(map(isValid, instruction.input_ports)));
    //     $display("Outputs done: %s and selected_outputs: %s", fshow(done_outputs), fshow(map(isValid, instruction.output_ports)));
    //     // $finish(-1);
    // endrule

    method ActionValue#(InstructionIdx) get_instruction_request();
        instruction_request.deq;
        return instruction_request.first;
    endmethod

    method ActionValue#(ChannelMessage) get(Integer port_id);
        external_outputs[port_id].deq;
        return external_outputs[port_id].first;
    endmethod

    method Action put(Integer port_id, ChannelMessage msg);
        inputs[port_id].enq(msg);
    endmethod

    method Action put_instruction(PCUAndTargetConfig instruction);
        instruction_response.enq(instruction);
    endmethod

    method Action done();
        // todo.
    endmethod
endmodule

module mkPCUReconfigurationTest(Empty);
    PCU_IFC pcu <- mkPCU;
    Reg#(Int#(32)) state <- mkReg(0);
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

    InstructionIdx dummy_idx = 0;
    InstructionIdx dummy_idx_2 = 1;

    Instruction_Ptr dummy_ptr = Instruction_Ptr {
        instruction_idx: dummy_idx,
        compute_type: ComputeType_PCU
    };

    Instruction_Ptr dummy_ptr_2 = Instruction_Ptr {
        instruction_idx: dummy_idx_2,
        compute_type: ComputeType_PCU
    };

    PCUInstruction repeat_static_instruction = PCUInstruction {
        op: tagged Tag_RepeatStatic RepeatStaticConfig {count: 2},
        input_ports: input_select_1,
        output_ports: output_select_1,
        debug_id: 1
    };

    rule incr_cycle;
        cycle <= cycle + 1;
    endrule

    mkAutoFSM( 
        par
            seq // Data Inputs
                action
                    pcu.put(0, tagged Tag_Instruction dummy_ptr);
                    pcu.put(1, tagged Tag_Instruction dummy_ptr);
                endaction
                action
                    pcu.put_instruction(PCUAndTargetConfig {
                        pcu_config: add_instruction,
                        target: ComponentTarget {
                            port_mappings: cons(tagged Valid dummy_ptr_2, replicate(tagged Invalid))
                        }
                    });
                    pcu.put(0, tagged Tag_Data zero_tile);
                    pcu.put(1, tagged Tag_Data one_tile);
                endaction
                action
                    pcu.put(0, tagged Tag_EndToken);
                    pcu.put(1, tagged Tag_EndToken);
                endaction
                action
                    pcu.put_instruction(PCUAndTargetConfig {
                        pcu_config: repeat_static_instruction,
                        target: ComponentTarget {
                            port_mappings: cons(tagged Valid dummy_ptr, replicate(tagged Invalid))
                        }
                    });
                    pcu.put(1, tagged Tag_Instruction dummy_ptr_2);
                endaction
                action
                    pcu.put(0, tagged Tag_Data two_tile);
                endaction
                action
                    pcu.put(0, tagged Tag_EndToken);
                endaction
            endseq
            seq // Data Outputs
                repeat (8)
                    action
                        let result <- pcu.get(0);
                        $display("Cycle %d: Result: ", cycle, fshow(result));
                    endaction
            endseq 
            seq // Instruction Requests
                action
                    let t <- pcu.get_instruction_request();
                    $display("Cycle %d: Instruction request %d", cycle, t);
                endaction
                action
                    let t <- pcu.get_instruction_request();
                    $display("Cycle %d: Instruction request %d", cycle, t);
                endaction
            endseq 
        endpar
    );
    
endmodule