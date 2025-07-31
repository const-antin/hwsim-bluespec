import Operation::*;
import RamulatorArbiter::*;
import Debug::*;
import FShow::*;

module mkSingleArbiter(Empty);
    RamulatorArbiter_IFC#(1) arbiter <- mkRamulatorArbiter(1);
    Reg#(Int#(64)) cc <- mkReg(0);
    Reg#(Int#(64)) count <- mkReg(0);

    rule cc_rule;
        cc <= cc + 1;
    endrule

    let mod_0 <- mkTileReader(128, "step_paper_14/address_reader_518.hex", 0, arbiter.ports);

    rule mod_0_output;
        let msg <- mod_0.get(0);
        $display("mod_0 output %d at cycle %d", count, cc);
        count <= count + 1;
    endrule
endmodule

module mkArbiterStressTest(Empty);
    RamulatorArbiter_IFC#(4) arbiter <- mkRamulatorArbiter(4);

    let cc <- mkReg(0);

    let mod_0 <- mkTileReader(2048, "gen_bsv/address_reader_0.hex", 0, arbiter.ports);
    let mod_1 <- mkTileReader(2048, "gen_bsv/address_reader_1.hex", 1, arbiter.ports);
    let mod_2 <- mkTileReader(2048, "gen_bsv/address_reader_2.hex", 2, arbiter.ports);
    let mod_3 <- mkTileReader(2048, "gen_bsv/address_reader_12.hex", 3, arbiter.ports);
    

    rule cc_rule;
        cc <= cc + 1;
    endrule

    rule mod_0_output;
        let msg <- mod_0.get(0);
        $display("mod_0 output: %d at cycle %d", fshow(msg), cc);
    endrule

    rule mod_1_output if (cc % 8 == 0);
        let msg <- mod_1.get(0);
        $display("mod_1 output:", fshow(msg));
    endrule

    rule mod_2_output if (cc % 512 == 0);
        let msg <- mod_2.get(0);
        $display("mod_2 output:", fshow(msg));
    endrule

    rule mod_3_output if (cc % 1024 == 0);
        let msg <- mod_3.get(0);
        $display("mod_3 output:", fshow(msg));
    endrule
endmodule