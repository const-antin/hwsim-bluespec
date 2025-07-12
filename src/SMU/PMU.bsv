package PMU;

import FIFO::*;
import Types::*;
import Vector::*;
import RegFile::*;
import BankedMemory::*;
import Parameters::*;
import SetFreeList::*;
import SetUsageTracker::*;

// Tracking the current storage location
typedef struct {
    SETS_LOG set;
    FRAMES_PER_SET_LOG frame;
    Bool valid;
} StorageLocation deriving(Bits, Eq);

// Interface that just exposes the modules existence
interface PMU_IFC;
endinterface

// PMU module that processes between the FIFOs
module mkPMU#(
    FIFO#(ChannelMessage) data_in,      // Values come in here
    FIFO#(ChannelMessage) token_out,    // Generated tokens go out here
    FIFO#(ChannelMessage) token_in,     // Tokens come back in here
    FIFO#(ChannelMessage) data_out      // Retrieved values go out here
)(PMU_IFC);
    
    // Only internal state needed is the storage FIFO and token counter
    BankedMemory_IFC mem <- mkBankedMemory;
    SetFreeList_IFC free_list <- mkSetFreeList;
    SetUsageTracker_IFC usage_tracker <- mkSetUsageTracker;
    Reg#(StorageLocation) curr_loc <- mkReg(StorageLocation { set: 0, frame: 0, valid: False });

    rule store_tile;
        let d_in = data_in.first;
        data_in.deq;

        case (d_in) matches
            tagged Tag_Data {.tt, .st}: begin
                case (tt) matches
                    tagged Tag_Tile .tile: begin
                        StorageLocation new_loc = curr_loc;
                        Int#(32) token = 0;

                        if (!curr_loc.valid) begin
                            let mset <- free_list.allocSet();
                            case (mset) matches
                                tagged Valid .set: begin
                                    mem.write(set, 0, TaggedTile { t: tile, st: st });
                                    usage_tracker.setFrame(set, 1);

                                    FRAMES_PER_SET_LOG zero_frame = 0;
                                    token = zeroExtend(unpack({ pack(set), pack(zero_frame) }));
                                    new_loc = StorageLocation { set: set, frame: 1, valid: True };
                                end
                                default: begin
                                    $display("***** Out of memory *****");
                                    $finish;
                                end
                            endcase
                        end else begin
                            let set = curr_loc.set;
                            let frame = curr_loc.frame;

                            mem.write(set, frame, TaggedTile { t: tile, st: st });
                            let full <- usage_tracker.incFrame(set);

                            token = zeroExtend(unpack({ pack(set), pack(frame) }));
                            new_loc = StorageLocation {
                                set: set,
                                frame: frame + 1,
                                valid: !full
                            };
                        end

                        token_out.enq(tagged Tag_Data tuple2(tagged Tag_Scalar token, st));
                        curr_loc <= new_loc;
                    end
                    tagged Tag_Ref .r: begin
                        $display("Reference received");
                        $finish(0);
                    end
                    tagged Tag_Scalar .scalar: begin
                        $display("Scalar received");
                        $finish(0);
                    end
                endcase
            end
            tagged Tag_Instruction .ip: begin
                $display("Instruction received"); // TODO: Should be able to accept incoming config
                $finish(0);
            end
            tagged Tag_EndToken .et: begin
                token_out.enq(tagged Tag_EndToken et);
                $display("End token received in store");
            end
        endcase
    endrule

    // Rule to handle token retrievals: find matching value and return it
    rule load_tile;
        let token_msg = token_in.first;
        token_in.deq;
        
        case (token_msg) matches
            tagged Tag_Data {.tt, .st}: begin
                case (tt) matches
                    tagged Tag_Scalar .token: begin
                        let token_bits = pack(token);
                        
                        let frame_width = valueOf(TLog#(FRAMES_PER_SET));
                        let set_width = valueOf(TLog#(SETS));
                        SETS_LOG set = token_bits[frame_width + set_width - 1 : frame_width];
                        FRAMES_PER_SET_LOG frame = token_bits[frame_width - 1 : 0];

                        let tile = mem.read(set, frame);
                        data_out.enq(tagged Tag_Data tuple2(tagged Tag_Tile tile.t, tile.st));
                    end
                    default: begin
                        $display("Expected scalar token");
                        $finish(0);
                    end
                endcase
            end
            tagged Tag_EndToken .et: begin
                // Print the state of the memory being used
                for (Integer i = 0; i < valueOf(SETS); i = i + 1) begin
                    // Check if set is valid
                    if (!free_list.isSetFree(fromInteger(i))) begin
                        $display("[MEMORY USAGE]: Set %d: %d frames used", i, usage_tracker.getCount(fromInteger(i)));
                    end else begin
                        $display("[MEMORY USAGE]: Set %d: No frames used", i);
                    end
                end
                data_out.enq(tagged Tag_EndToken et);
                $display("End token received");
            end
            default: begin
                $display("Expected data message with token");
                $finish(0);
            end
        endcase
    endrule

endmodule

endpackage