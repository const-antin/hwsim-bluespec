package Interconnect;

import Types::*;
import Vector::*;
import FIFO::*;
import Parameters::*;
import PCUInstruction::*;

interface Interconnect_IFC;
    method Action add_instruction(Instruction instruction);

    method Action put_pcu(Integer pcu_idx, Integer port_idx, ChannelMessage msg);
    method ActionValue#(ChannelMessage) get_pcu(Integer pcu_idx, Integer port_idx);

    method Action put_pmu(Integer pmu_idx, Integer port_idx, ChannelMessage msg);
    method ActionValue#(ChannelMessage) get_pmu(Integer pmu_idx, Integer port_idx);
endinterface

module mkInterconnect(Interconnect_IFC);
    Vector#(NUM_PCUS, Vector#(NUM_INPUTS_PER_PCU, FIFO#(ChannelMessage))) pcu_input_fifos <- replicateM(replicateM(mkFIFO));
    Vector#(NUM_PCUS, Vector#(NUM_OUTPUTS_PER_PCU, FIFO#(ChannelMessage))) pcu_output_fifos <- replicateM(replicateM(mkFIFO));

    Vector#(NUM_PMUS, Vector#(NUM_INPUTS_PER_PMU, FIFO#(ChannelMessage))) pmu_input_fifos <- replicateM(replicateM(mkFIFO));
    Vector#(NUM_PMUS, Vector#(NUM_OUTPUTS_PER_PMU, FIFO#(ChannelMessage))) pmu_output_fifos <- replicateM(replicateM(mkFIFO));

    method Action put_pcu(Integer pcu_idx, Integer port_idx, ChannelMessage msg);
        pcu_input_fifos[pcu_idx][port_idx].enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get_pcu(Integer pcu_idx, Integer port_idx);
        pcu_output_fifos[pcu_idx][port_idx].deq;
        return pcu_output_fifos[pcu_idx][port_idx].first;
    endmethod
    
    method Action put_pmu(Integer pmu_idx, Integer port_idx, ChannelMessage msg);
        pmu_input_fifos[pmu_idx][port_idx].enq(msg);
    endmethod

    method ActionValue#(ChannelMessage) get_pmu(Integer pmu_idx, Integer port_idx);
        pmu_output_fifos[pmu_idx][port_idx].deq;
        return pmu_output_fifos[pmu_idx][port_idx].first;
    endmethod
endmodule

endpackage