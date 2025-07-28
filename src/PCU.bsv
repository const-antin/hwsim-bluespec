import Types::*;
import Vector::*;
import FIFO::*;
import Parameters::*;
import Instructions::*;
import Operation::*;
import ALU::*;
import StmtFSM::*;

interface PCU_IFC;
    method Action put_instruction(Instruction instruction);
    method ActionValue#(Instruction_Ptr) get_instruction_request();
    method ActionValue#(ChannelMessage) get(Integer port);
    method Action put(Integer port, ChannelMessage msg);
    method Action done();
endinterface

typedef union tagged {
    void Tag_Idle;
    Instruction_Ptr Tag_Requesting_Config;
    void Tag_Waiting_For_Config;
    Instruction Tag_Computing;
} PCUState deriving (Bits, Eq, FShow);

module mkPCU(PCU_IFC);
    ALU_IFC alu <- mkALU;
    Accum_IFC accum <- mkAccum(alu);
    RepeatStatic_IFC repeat_static <- mkRepeatStatic;
    UnaryMap_IFC unary_map <- mkUnaryMap(alu);
    BinaryMap_IFC binary_map <- mkBinaryMap(alu);
    Promote_IFC promote <- mkPromote;
    AccumBigTile_IFC accum_big_tile <- mkAccumBigTile(alu);
    
    // Stub modules for missing operations
    Broadcast_IFC broadcast <- mkBroadcast;
    Concat_IFC concat <- mkConcat;
    Enumerate_IFC enumerate <- mkEnumerate;
    Flatten_IFC flatten <- mkFlatten;
    FlatMap_IFC flatmap <- mkFlatMap;
    RepeatN_IFC repeat_n <- mkRepeatN;
    RepeatRef_IFC repeat_ref <- mkRepeatRef;
    Reshape_IFC reshape <- mkReshape;
    Reassemble_IFC reassemble <- mkReassemble;
    Rotate_IFC rotate <- mkRotate;
    Parallelize_IFC parallelize <- mkParallelize;
    Partition_IFC partition <- mkPartition;
    Scan_IFC scan <- mkScan;
    SpatialMatmulT_IFC spatial_matmul_t <- mkSpatialMatmulT;

    Vector#(NUM_INPUTS_PER_PCU, FIFO#(ChannelMessage)) inputs <- replicateM(mkFIFO);
    Vector#(NUM_OUTPUTS_PER_PCU, FIFO#(ChannelMessage)) outputs <- replicateM(mkFIFO);

    Reg#(PCUState) state <- mkReg(tagged Tag_Idle);
    Reg#(Bit#(NUM_INPUTS_PER_PCU)) selected_inputs <- mkReg(0);
    Reg#(Bit#(NUM_INPUTS_PER_PCU)) done_inputs <- mkReg(0);

    FIFO#(Instruction_Ptr) insturction_request <- mkFIFO;
    FIFO#(Instruction) instruction_response <- mkFIFO;

    // Configure the PCU to the next instruction
    for (Integer i = 0; i < fromInteger(valueOf(NUM_INPUTS_PER_PCU)); i = i + 1) begin
        rule configure if (inputs[i].first matches tagged Tag_Instruction .instruction_ptr);
            if (state matches tagged Tag_Idle) begin
                state <= tagged Tag_Requesting_Config instruction_ptr;
                inputs[i].deq;
            end else begin
                inputs[i].deq;
            end
        endrule
    end

    rule request_config if (state matches tagged Tag_Requesting_Config .instruction_ptr);
        insturction_request.enq(instruction_ptr);
        state <= tagged Tag_Waiting_For_Config;
    endrule

    rule program_config if (state matches tagged Tag_Waiting_For_Config);
        let instruction = instruction_response.first;
        instruction_response.deq;
        state <= tagged Tag_Computing instruction;

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
    endrule

    // Handle input to compute unit while being configured
    for (Integer i = 0; i < fromInteger(valueOf(NUM_INPUTS_PER_PCU)); i = i + 1) begin
        rule handle_compute_input if (state matches tagged Tag_Computing .current_op &&& selected_inputs[i:i] == 1 &&& inputs[i].first matches tagged Tag_Data .data);
            InstructionOp op = current_op.op;
            let in = inputs[i].first;
            inputs[i].deq;
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

            if (inputs[idx].first matches tagged Tag_EndToken .tk) begin
                done_inputs[idx] <= 1;
            end
        endrule
    end

    // Transition: Configuring -> Idle
    rule config_to_idle if (state matches tagged Tag_Computing .instruction &&& selected_inputs == done_inputs);
        state <= tagged Tag_Idle;
    endrule    

    method ActionValue#(Instruction_Ptr) get_instruction_request();
        return insturction_request.first;
    endmethod

    method ActionValue#(ChannelMessage) get(Integer port_id);
        return outputs[port_id].first;
    endmethod

    method Action put(Integer port_id, ChannelMessage msg);
        outputs[port_id].enq(msg);
    endmethod

    method Action done();
        done_inputs <= 0;
    endmethod
endmodule

module mkPCUReconfigurationTest(Empty);
    PCU_IFC pcu <- mkPCU;
    Reg#(Int#(32)) state <- mkReg(0);
    Reg#(Int#(32)) cycle <- mkReg(0);

    Tuple2#(Data, StopToken) zero_tile = tuple2(tagged Tag_Tile 0, 0);
    Tuple2#(Data, StopToken) one_tile = tuple2(tagged Tag_Tile 1, 0);
    Tuple2#(Data, StopToken) two_tile = tuple2(tagged Tag_Tile 2, 0);

    Vector#(1, Maybe#(UInt#(TLog#(NUM_INPUTS_PER_PCU)))) input_select_1 = cons(tagged Valid 0, nil);
    Vector#(2, Maybe#(UInt#(TLog#(NUM_INPUTS_PER_PCU)))) input_select_2 = cons(tagged Valid 0, cons(tagged Valid 1, nil));
    Vector#(1, Maybe#(UInt#(TLog#(NUM_OUTPUTS_PER_PCU)))) output_select_1 = cons(tagged Valid 0, nil);
    
    Instruction add_instruction = Instruction {
        op: tagged Tag_BinaryMap BinaryMapConfig {op: ADD},
        input_ports: unpack(extend(pack(input_select_2))),
        output_ports: unpack(extend(pack(output_select_1))),
        debug_id: 0
    };

    Instruction_Ptr dummy_ptr = Instruction_Ptr {
        ptr: 0,
        port_idx: 0
    };

    Instruction repeat_static_instruction = Instruction {
        op: tagged Tag_RepeatStatic RepeatStaticConfig {count: 1},
        input_ports: unpack(extend(pack(input_select_1))),
        output_ports: unpack(extend(pack(output_select_1))),
        debug_id: 1
    };

    mkAutoFSM( 
        par
            seq
                action
                    pcu.put(0, tagged Tag_Instruction dummy_ptr);
                    pcu.put(1, tagged Tag_Instruction dummy_ptr);
                endaction
                action
                    pcu.put_instruction(add_instruction);
                    pcu.put(0, tagged Tag_Instruction dummy_ptr);
                    pcu.put(1, tagged Tag_Instruction dummy_ptr);
                endaction
                action
                    pcu.put(0, tagged Tag_EndToken);
                    pcu.put(1, tagged Tag_EndToken);
                endaction
                action
                    pcu.put_instruction(repeat_static_instruction);
                    pcu.put(0, tagged Tag_Instruction dummy_ptr);
                endaction
            endseq
            seq
                action
                    let result <- pcu.get(0);
                    $display("Cycle %d: Result %d", cycle, result);
                endaction
                action
                    let result <- pcu.get(0);
                    $display("Cycle %d: Result %d", cycle, result);
                endaction
            endseq 
            seq
                action
                    let result <- pcu.get_instruct
            endseq 
        endpar
    );
    
endmodule