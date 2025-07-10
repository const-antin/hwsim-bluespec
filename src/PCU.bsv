import Types::*;
import Vector::*;
import FIFO::*;
import Parameters::*;
import PCUInstruction::*;

interface PCU_IFC;
    method Action put_instruction(Instruction instruction);
    method ActionValue#(ChannelMessage) get(Integer port);
    method Action put(Integer port, ChannelMessage msg);
    method Action done();
endinterface

module mkPCU(PCU_IFC);
    Reg#(Insturction) 
endmodule