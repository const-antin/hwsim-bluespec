// TODO: Make everything work in fifo order. I think this should immediately work as long as I emit the token earlier. 
    // I already have the logic necessary to make sure i don't read data that hasn't been stored (untested)
// TODO: Replace loop with find
// TODO: Remove memory size dependency on tile size, should just have banks be as large as possible
// TODO: Swap registers for SRAM
// TODO: rank shouldnt be a parameter, should be stored in a reg and parsed from a config input
// TODO: Fair aribitration between directions data is sent, currently prioritizes north, then south, then west, then east.
// TODO: Tag pmus as bufferizes and dont store to neighbors if theyre also a bufferize
// TODO: pipeline reads

package PMU;

import FIFOF::*;
import Types::*;
import Vector::*;
import RegFile::*;
import ConfigReg::*;
import BankedMemory::*;
import Parameters::*;
import SetFreeList::*;
import SetUsageTracker::*;
import Unwrap::*;
import Operation::*;
import HelperFunctions::*;

// Interface that just exposes the modules existence
interface PMU_IFC;
    interface Operation_IFC operation;
    method Action put_data(ChannelMessage msg);
    method ActionValue#(ChannelMessage) get_token();
    method Action put_token(ChannelMessage msg);
    method ActionValue#(ChannelMessage) get_data();
    method Int#(32) get_cycle_count();
endinterface

// PMU module that processes between the FIFOs
module mkPMU#(
    Int#(32) rank,                    // Rank of the current tile
    Coords coords, // x, y
    Vector#(4, FIFOF#(MessageType)) request_data, // North, South, West, East
    Vector#(4, FIFOF#(MessageType)) receive_request_data,
    Vector#(4, FIFOF#(MessageType)) send_data,
    Vector#(4, FIFOF#(MessageType)) receive_send_data,
    Vector#(4, FIFOF#(MessageType)) request_space,
    Vector#(4, FIFOF#(MessageType)) receive_request_space,
    Vector#(4, FIFOF#(MessageType)) send_space,
    Vector#(4, FIFOF#(MessageType)) receive_send_space,
    Vector#(4, FIFOF#(MessageType)) send_dealloc,
    Vector#(4, FIFOF#(MessageType)) receive_send_dealloc,
    Vector#(4, FIFOF#(MessageType)) send_update_pointer,
    Vector#(4, FIFOF#(MessageType)) receive_send_update_pointer
)(PMU_IFC);
    // ============================================================================
    // Internal state
    // ============================================================================

    FIFOF#(ChannelMessage) data_in <- mkFIFOF;      // Values come in here
    FIFOF#(ChannelMessage) token_out <- mkGFIFOF(True, False);    // Generated tokens go out here
    FIFOF#(ChannelMessage) token_in <- mkFIFOF;     // Tokens come back in here
    FIFOF#(ChannelMessage) data_out <- mkFIFOF;     // Retrieved values go out here

    // initialization and cycle count
    Reg#(Bit#(32)) cycle_count <- mkReg(0);
    Reg#(Bool) initialized <- mkReg(False);
    Reg#(TokID) first_entry_initialized_index <- mkReg(0);
    ConfigReg#(TokID) token_counter <- mkConfigReg(0);

    // storage usage tracking
    BankedMemory_IFC mem <- mkBankedMemory;
    SetFreeList_IFC free_list <- mkSetFreeList;
    SetUsageTracker_IFC usage_tracker <- mkSetUsageTracker;
    Reg#(Maybe#(StorageAddr)) curr_loc <- mkReg(tagged Invalid);
    Reg#(Maybe#(StorageAddr)) prev_loc <- mkReg(tagged Invalid);
    ConfigReg#(Maybe#(StorageAddr)) next_free_set <- mkConfigReg(tagged Invalid);
    ConfigReg#(Bit#(32)) num_stored_to_current_frame <- mkConfigReg(0);

    // storage chain logic
    RegFile#(TokID, Maybe#(StorageAddr)) first_entry <- mkRegFileWCF(0, fromInteger(valueOf(MAX_ENTRIES) - 1));    
    RegFile#(TokID, Bool) token_complete <- mkRegFileWCF(0, fromInteger(valueOf(MAX_ENTRIES) - 1));
    Vector#(MAX_ENTRIES, ConfigReg#(Maybe#(StorageAddr))) next_table <- replicateM(mkConfigReg(tagged Invalid));
    Reg#(StorageAddr) prev_stored <- mkReg(StorageAddr { set: 0, frame: 0, coords: coords });

    // load and deallocate registers
    ConfigReg#(Maybe#(LoadState)) load_token <- mkConfigReg(tagged Invalid);
    Wire#(Maybe#(TokID)) deallocate_reg <- mkDWire(tagged Invalid);

    // In flight trackers
    Reg#(Bool) space_request_in_flight <- mkReg(False);
    Reg#(Bool) seen_yes <- mkReg(False);
    Reg#(Int#(32)) num_responses_received <- mkReg(0);
    Reg#(Int#(32)) num_space_requests_in_flight <- mkReg(0);
    ConfigReg#(Bool) data_request_in_flight <- mkConfigReg(False);
    ConfigReg#(Bool) readReq_in_flight <- mkConfigReg(False);

    // Round robin counters
    Reg#(Dir) space_round_robin_counter <- mkReg(0);
    Reg#(Dir) dealloc_round_robin_counter <- mkReg(0);
    Reg#(Dir) receive_send_data_round_robin_counter_store <- mkReg(0);
    Reg#(Dir) receive_send_data_round_robin_counter_load <- mkReg(0);
    Reg#(Dir) receive_request_data_round_robin_counter <- mkReg(0);
    Reg#(Dir) receive_send_update_pointer_round_robin_counter <- mkReg(0);
    ConfigReg#(Bool) which_rule_reads_rr <- mkConfigReg(False); // True for request_tile, False for continue_load_tile, round robin
    Wire#(Bool) which_rule_reads <- mkDWire(False); // True for request_tile, False for continue_load_tile, which actually reads
    FIFOF#(RespTag) mem_rsp_src <- mkFIFOF;
    FIFOF#(PendingReq) pending_q <- mkGFIFOF(False, True);
    FIFOF#(LoadMeta)   load_meta_q <- mkGFIFOF(False, True);
    // ConfigReg#(Maybe#(PendingReq)) pending   <- mkConfigReg(tagged Invalid);
    // ConfigReg#(Maybe#(LoadMeta))   load_meta <- mkConfigReg(tagged Invalid);

    // directional selection wires
    Wire#(Maybe#(Dir)) request_space_wire <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Dir)) receive_deallocate_wire <- mkDWire(tagged Invalid);
    Vector#(4, Reg#(Bool)) send_request_space_wire <- replicateM(mkDWire(False));
    Wire#(Maybe#(Tuple2#(DataWithNext, Dir))) receive_request_data_send_data <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Tuple2#(Dir, RequestStorageAddr))) continue_load_tile_request_data <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Dir)) store_direction <- mkDWire(tagged Invalid);
    Vector#(4, Wire#(Maybe#(StorageAddr))) dealloc_wire <- replicateM(mkDWire(tagged Invalid));
    Wire#(Maybe#(Tuple2#(Data, StopToken))) receive_send_data_output <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Tuple2#(RequestStorageAddr, Dir))) receive_request_data_dequeued_wire <- mkDWire(tagged Invalid);
    ConfigReg#(Maybe#(Tuple2#(RequestStorageAddr, Dir))) receive_request_data_reg <- mkConfigReg(tagged Invalid);

    // ============================================================================
    // Rule Orderings
    // ============================================================================

    (* execution_order = "round_robin_space_request, receive_send_space, store_tile, next_free" *)
    (* execution_order = "start_load_tile, receive_send_data" *)
    (* execution_order = "receive_deallocate, receive_request_data, next_free" *)
    (* execution_order = "receive_request_data_do_work, next_free" *)
    (* execution_order = "receive_send_update_pointer, receive_send_data" *)
    (* execution_order = "store_tile, receive_send_update_pointer" *)
    (* execution_order = "receive_send_space, round_robin_space_request_enact, next_free" *)
    (* execution_order = "continue_load_tile, next_free" *)
    (* execution_order = "receive_deallocate_enact, next_free" *)
    (* execution_order = "receive_data_from_banked_mem, next_free" *)
    (* execution_order = "continue_load_tile, receive_data_from_banked_mem" *)
    (* execution_order = "start_load_tile, receive_data_from_banked_mem" *)
    (* execution_order = "receive_request_data_do_work, receive_data_from_banked_mem" *)
    (* descending_urgency = "deallocate_token, store_tile, round_robin_space_request" *)
    (* descending_urgency = "store_tile, receive_send_data" *)
    (* descending_urgency = "store_tile, receive_request_data, receive_request_data_enq" *)
    (* descending_urgency = "space_request_no_0, space_request_no_1, space_request_no_2, space_request_no_3, round_robin_space_request" *)
    (* conflict_free = "receive_send_data, continue_load_tile" *)
    (* conflict_free = "receive_data_from_banked_mem, receive_send_data" *)
    (* conflict_free = "receive_send_data_enq, continue_load_tile" *)
    (* mutually_exclusive = "space_request_no_0, round_robin_space_request_enact" *)
    (* mutually_exclusive = "space_request_no_1, round_robin_space_request_enact" *)
    (* mutually_exclusive = "space_request_no_2, round_robin_space_request_enact" *)
    (* mutually_exclusive = "space_request_no_3, round_robin_space_request_enact" *)
    (* mutually_exclusive = "receive_send_data_enq, start_load_end_token" *)

    // ============================================================================
    // Main Logic Rules
    // ============================================================================

    rule round_robin_space_request (initialized &&& isValid(next_free_set) &&& next_free_set.Valid.coords == coords);
        Vector#(4, Bool) has_data = map(notEmptyNotFull, zip(receive_request_space, send_space));
        request_space_wire <= roundRobinFind(space_round_robin_counter, has_data);
    endrule
    rule round_robin_space_request_enact (request_space_wire matches tagged Valid .idx);
        receive_request_space[idx].deq;
        send_space[idx].enq(tagged Tag_FreeSpaceYes StorageAddr { set: next_free_set.Valid.set, frame: 0, coords: coords });
        next_free_set <= tagged Invalid;
        space_round_robin_counter <= idx + 1;
    endrule

    rule receive_deallocate (initialized);
        Vector#(4, Bool) has_data = map(notEmpty, receive_send_dealloc);
        receive_deallocate_wire <= roundRobinFind(dealloc_round_robin_counter, has_data);
    endrule
    rule receive_deallocate_enact (receive_deallocate_wire matches tagged Valid .idx);
        receive_send_dealloc[idx].deq;
        let loc = receive_send_dealloc[idx].first.Tag_Deallocate;
        free_list.freeSet(loc.set);
        dealloc_round_robin_counter <= idx + 1;
    endrule

    rule receive_send_space (initialized && space_request_in_flight);
        Vector#(4, Bool) has_data = map(notEmptyNotFull, zip(receive_send_space, send_dealloc));
        Bool seen_yes_temp = False;
        Int#(32) num_responses_temp = 0;
        
        for (Integer i = 0; i < 4; i = i + 1) begin
            if (has_data[i]) begin
                receive_send_space[i].deq;
                num_responses_temp = num_responses_temp + 1;
                if (receive_send_space[i].first matches tagged Tag_FreeSpaceYes .loc) begin
                    if (!seen_yes && !seen_yes_temp) begin
                        next_free_set <= tagged Valid loc;
                    end else begin
                        dealloc_wire[i] <= tagged Valid loc;
                    end
                    seen_yes_temp = True;
                end
            end
        end

        let seen_all_responses = num_responses_received + num_responses_temp == num_space_requests_in_flight;
        seen_yes                <= seen_all_responses ? False : seen_yes || seen_yes_temp;
        num_responses_received  <= seen_all_responses ? 0     : num_responses_received + num_responses_temp;
        space_request_in_flight <= seen_all_responses ? False : space_request_in_flight;
    endrule

    rule next_free (initialized && !isValid(next_free_set) && !space_request_in_flight);
        let mset <- free_list.allocSet();
        case (mset) matches
            tagged Valid .s: begin
                next_free_set <= tagged Valid StorageAddr { set: s, frame: 0, coords: coords };
            end
            default: begin
                $display("***** Out of memory at PMU %d, %d *****", coords.x, coords.y);
                next_free_set <= tagged Invalid;
                Int#(32) num_requests_sent = 0;
                for (Int#(32) i = 0; i < 4; i = i + 1) begin
                    if (request_space[i].notFull && canSendInDirection(i, coords)) begin
                        send_request_space_wire[i] <= True;
                        num_requests_sent = num_requests_sent + 1;
                    end
                end
                if (num_requests_sent == 0) begin 
                    $display("Cannot send space request to any direction at PMU %d, %d", coords.x, coords.y);
                end else begin
                    space_request_in_flight <= True;
                    num_space_requests_in_flight <= num_requests_sent;
                end
            end
        endcase
    endrule

    rule receive_send_data (initialized);
        function notEmptyAndStore(x) = x.notEmpty &&& isStore(x.first);
        Vector#(4, Bool) has_store_data = map(notEmptyAndStore, receive_send_data);
        function notEmptyAndLoad(x) = data_out.notFull &&& data_request_in_flight &&& x.fst.notEmpty &&& isLoad(x.fst.first) &&& !x.snd;
        Vector#(4, Bool) has_load_data = map(notEmptyAndLoad, zip(receive_send_data, has_store_data));

        Maybe#(Dir) m_idx = roundRobinFind(receive_send_data_round_robin_counter_store, has_store_data);
        if (m_idx matches tagged Valid .idx) begin
            receive_send_data[idx].deq;
            let data_with_next = receive_send_data[idx].first.Tag_Store;
            let data = data_with_next.data;
            let loc = data_with_next.loc;
            mem.write(loc.set, loc.frame, data);
            if (loc.frame > 0) begin
                let old_loc = StorageAddr { set: loc.set, frame: loc.frame - 1, coords: loc.coords };
                next_table[storageAddrToIndex(old_loc)] <= tagged Valid loc;
            end
            next_table[storageAddrToIndex(loc)] <= tagged Invalid;
            receive_send_data_round_robin_counter_store <= idx + 1;
        end

        Maybe#(Dir) m_idx2 = roundRobinFind(receive_send_data_round_robin_counter_load, has_load_data);
        if (m_idx2 matches tagged Valid .idx) begin
            $display("Actually received data back from neighbor at PMU %d, %d", coords.x, coords.y);
            receive_send_data[idx].deq;
            let data_with_next = receive_send_data[idx].first.Tag_Load;
            let data = data_with_next.data;
            let loc = data_with_next.loc;
            let next = data_with_next.next;
            $display("Validity of next: %b", isValid(next));
            let out_rank = !isValid(next) ? rank + load_token.Valid.st : data.st;
            Bool send_next_request = isValid(next) && next.Valid.set != loc.set; // auto loading next frame means we dont need to request the next frame
            if (send_next_request || !isValid(next)) begin
                data_request_in_flight <= False; // if we need to send the next request, or no next exists, then the data is no longer in flight
            end
            load_token <= !send_next_request ? tagged Invalid : tagged Valid LoadState { loc: next.Valid, deallocate: load_token.Valid.deallocate, st: load_token.Valid.st, orig_token: load_token.Valid.orig_token };
            receive_send_data_output <= tagged Valid tuple2(tagged Tag_Tile data.t, out_rank);
            receive_send_data_round_robin_counter_load <= idx + 1;
        end
    endrule
    rule receive_send_data_enq (receive_send_data_output matches tagged Valid .out);
        data_out.enq(tagged Tag_Data out);
    endrule

    rule which_read (initialized);
        Bool request_tile_can_read = isValid(roundRobinFind(receive_request_data_round_robin_counter, map(notEmpty, receive_request_data))) || isValid(receive_request_data_reg);
        Bool continue_load_tile_can_read = isValid(load_token) &&& !data_request_in_flight &&& !readReq_in_flight &&& (load_token.Valid.loc.coords == coords &&& data_out.notFull || load_token.Valid.loc.coords != coords &&& request_data[neighIdx(coords, load_token.Valid.loc.coords)].notFull);
        if (request_tile_can_read && !continue_load_tile_can_read) begin
            which_rule_reads <= True; // request_tile can read
        end else if (continue_load_tile_can_read && !request_tile_can_read) begin
            which_rule_reads <= False; // continue_load_tile can read
        end else if (request_tile_can_read && continue_load_tile_can_read) begin
            which_rule_reads <= which_rule_reads_rr; // both can read, so we alternate
            which_rule_reads_rr <= !which_rule_reads_rr;
        end
    endrule

    rule receive_request_data (initialized &&& which_rule_reads &&& !isValid(receive_request_data_reg)); // has read permission
        Vector#(4, Bool) has_data = map(notEmptyNotFull, zip(receive_request_data, send_data));
        Maybe#(Dir) m_idx = roundRobinFind(receive_request_data_round_robin_counter, has_data);
        if (m_idx matches tagged Valid .idx) begin
            $display("PMU %d, %d received request data from direction %d", coords.x, coords.y, idx);
            receive_request_data[idx].deq;
            receive_request_data_dequeued_wire <= tagged Valid tuple2(receive_request_data[idx].first.Tag_Request_Data, idx);
            receive_request_data_round_robin_counter <= idx + 1;
        end
    endrule
    rule receive_request_data_do_work ((isValid(receive_request_data_dequeued_wire) || isValid(receive_request_data_reg)) &&& which_rule_reads);
        $display("PMU %d, %d received request, doing work (reading mem)", coords.x, coords.y);
        let req_tuple = isValid(receive_request_data_dequeued_wire) ? receive_request_data_dequeued_wire.Valid : receive_request_data_reg.Valid;
        let req = tpl_1(req_tuple);
        let idx = tpl_2(req_tuple);
        let loc = req.loc;
        let next = next_table[storageAddrToIndex(loc)];
        mem.readReq(loc.set, loc.frame);
        mem_rsp_src.enq(FromReq);
        pending_q.enq(PendingReq { idx: idx, loc: loc, next: next, deallocate: req.deallocate });
        // let tile = mem.read(loc.set, loc.frame);
        // receive_request_data_send_data <= tagged Valid tuple2(DataWithNext { data: tile, loc: loc, next: next }, idx);
        if (req.deallocate &&& (!isValid(next) || loc.set != next.Valid.set)) begin
            free_list.freeSet(loc.set); 
        end
        // send data back
        // Update register for next cycle (only if we have a next location to process)
        if (isValid(next) && next.Valid.set == loc.set) begin
            $display("In the isvalid next condition, auto loading the next frame at pmu %d, %d", coords.x, coords.y);
            receive_request_data_reg <= tagged Valid tuple2(RequestStorageAddr {loc: next.Valid, deallocate: req.deallocate}, idx);
        end else begin
            receive_request_data_reg <= tagged Invalid;
        end
    endrule
    rule receive_request_data_enq (receive_request_data_send_data matches tagged Valid .data_with_next);
        $display("Actually sending data back to neighbor at PMU %d, %d", coords.x, coords.y);
        send_data[tpl_2(data_with_next)].enq(tagged Tag_Load tpl_1(data_with_next));
    endrule

    rule receive_data_from_banked_mem (initialized);
        let src = mem_rsp_src.first; mem_rsp_src.deq;
        let m <- mem.readRsp;  // TaggedTile { t, st }

        case (src)
            FromReq: begin
                $display("PMU %d, %d received data from banked memory for request", coords.x, coords.y);
                let p = pending_q.first; pending_q.deq;
                receive_request_data_send_data <= tagged Valid tuple2(DataWithNext { data: m, loc: p.loc, next: p.next }, p.idx);
            end
            FromLoad: begin
                readReq_in_flight <= False; // read request is no longer in flight
                let meta = load_meta_q.first; load_meta_q.deq;
                let out_rank = m.st;
                let next_set = meta.loc.set + 1;

                if (meta.next matches tagged Valid .next_loc) begin
                    next_set = next_loc.set;
                    load_token <= tagged Valid LoadState { loc: next_loc, deallocate: meta.deallocate, st: meta.st, orig_token: meta.orig_token };
                end else begin
                    load_token <= tagged Invalid;
                    out_rank = rank + meta.st;
                    if (meta.deallocate) begin
                        deallocate_reg <= tagged Valid truncate(meta.orig_token);
                    end
                end

                receive_send_data_output <= tagged Valid tuple2(tagged Tag_Tile m.t, out_rank);

                if (meta.deallocate && coords == meta.loc.coords && (!isValid(meta.next) || meta.loc.set != meta.next.Valid.set)) begin
                    free_list.freeSet(meta.loc.set);
                end
            end
        endcase
        
    endrule

    rule receive_send_update_pointer (initialized);
        Vector#(4, Bool) has_data = map(notEmpty, receive_send_update_pointer);
        Maybe#(Dir) m_idx = roundRobinFind(receive_send_update_pointer_round_robin_counter, has_data);
        if (m_idx matches tagged Valid .idx) begin
            $display("PMU %d, %d received update pointer from direction %d", coords.x, coords.y, idx);
            receive_send_update_pointer[idx].deq;
            let upd = receive_send_update_pointer[idx].first.Tag_Update_Next_Table;
            next_table[storageAddrToIndex(upd.prev)] <= tagged Valid upd.next;
            receive_send_update_pointer_round_robin_counter <= idx + 1;
        end
    endrule

    rule store_tile (initialized && (isValid(next_free_set) || isValid(curr_loc)) &&& data_in.first matches tagged Tag_Data {.tt, .st});
        // initialization
        let tile = unwrapTile(tt);
        let {new_st, emit_token} = processStopToken(st, rank);

        Bool prev_coords_local = (prev_stored.coords == coords);
        Bool need_to_send_update_to_neighbor = isValid(first_entry.sub(token_counter)) && !prev_coords_local && prev_stored.frame == fromInteger(valueOf(FRAMES_PER_SET) - 1);
        Bool can_update_neighbor_if_needed = !need_to_send_update_to_neighbor || send_update_pointer[neighIdx(coords, prev_stored.coords)].notFull;

        Coords new_coords = isValid(curr_loc) ? curr_loc.Valid.coords : next_free_set.Valid.coords;
        SET_INDEX set =     isValid(curr_loc) ? curr_loc.Valid.set    : next_free_set.Valid.set;
        FRAME_INDEX frame = isValid(curr_loc) ? curr_loc.Valid.frame  : 0;
        Bool curr_coords_local = new_coords == coords;
        Bool send_to_neighbor_if_needed = curr_coords_local ? True : send_data[neighIdx(coords, new_coords)].notFull;

        // only update state once we know that we can process the incoming data however appropriate
        if ((!emit_token || token_out.notFull) && can_update_neighbor_if_needed && send_to_neighbor_if_needed) begin
            data_in.deq;
            if (emit_token) begin
                token_complete.upd(token_counter, True);
                token_out.enq(tagged Tag_Data tuple2(tagged Tag_Ref tuple2(zeroExtend(token_counter), True), new_st)); // token enq is unguarded
                token_counter <= token_counter + 1;
            end

            let full = num_stored_to_current_frame == fromInteger(valueOf(FRAMES_PER_SET) - 1);
            let is_full = full || emit_token;
            Maybe#(StorageAddr) new_loc  = is_full ? tagged Invalid : tagged Valid StorageAddr { set: set, frame: frame + 1, coords: new_coords };
            num_stored_to_current_frame <= is_full ? 0              : num_stored_to_current_frame + 1;

            let p = StorageAddr { set: set, frame: frame, coords: new_coords };
            if (curr_coords_local) begin
                usage_tracker.setFrame(set, zeroExtend(frame) + 1);
                mem.write(set, frame, TaggedTile { t: tile, st: st });
                next_table[storageAddrToIndex(p)] <= tagged Invalid;
            end else begin 
                send_data[neighIdx(coords, new_coords)].enq(tagged Tag_Store DataWithNext {data: TaggedTile { t: tile, st: st }, loc: p, next: new_loc}); // this is unguarded
            end

            // update the storage location pointer chain
            if (first_entry.sub(token_counter) matches tagged Invalid) begin
                first_entry.upd(token_counter, tagged Valid p);
            end else begin
                if (prev_coords_local && prev_stored != p) begin // prev_stored != p is to prevent compiler complaint about 2 updates to same location in next_table
                    next_table[storageAddrToIndex(prev_stored)] <= tagged Valid p;
                end
                // update pointer chain
                if (!prev_coords_local && prev_stored.frame == fromInteger(valueOf(FRAMES_PER_SET) - 1)) begin
                    send_update_pointer[neighIdx(coords, prev_stored.coords)].enq(tagged Tag_Update_Next_Table PrevToNextTag { prev: prev_stored, next: p }); // enq is unguarded
                end 
            end

            // update state
            if (!isValid(curr_loc)) begin
                next_free_set <= tagged Invalid;
            end 
            prev_loc <= curr_loc;
            curr_loc <= new_loc;
            prev_stored <= p;
        end
    endrule

    rule start_load_tile (initialized &&& !isValid(load_token) &&& token_in.first matches tagged Tag_Data {.tt, .st});
        token_in.deq;
        let token_input = unwrapRef(tt);
        let maybe_packed_loc = first_entry.sub(truncate(token_input.fst));
        if (maybe_packed_loc matches tagged Valid .p) begin
            load_token <= tagged Valid LoadState { loc: p, deallocate: token_input.snd, st: st, orig_token: truncate(token_input.fst) };
        end else begin
            $display("[ERROR]: Token %d not associated with any data", token_input.fst);
            $finish(0);
        end
    endrule

    rule continue_load_tile (initialized &&& load_token matches tagged Valid .load_tk_val &&& !data_request_in_flight &&& !which_rule_reads &&& !readReq_in_flight); // has read permission
        StorageAddr loc = load_tk_val.loc;
        let deallocate = load_tk_val.deallocate;
        let st = load_tk_val.st;
        let orig_token = load_tk_val.orig_token;

        Bool token_is_complete = token_complete.sub(orig_token);
        Maybe#(StorageAddr) has_next_piece = next_table[storageAddrToIndex(loc)]; // this isnt really relevant until FIFO

        if (token_is_complete || isValid(has_next_piece)) begin
            let set = loc.set;
            let dir = neighIdx(coords, loc.coords);
            if (coords != loc.coords && request_data[dir].notFull) begin
                data_request_in_flight <= True;
                continue_load_tile_request_data <= tagged Valid tuple2(dir, RequestStorageAddr { loc: loc, deallocate: deallocate });
            end else if (coords == loc.coords && data_out.notFull) begin
                readReq_in_flight <= True; 
                mem.readReq(loc.set, loc.frame);
                mem_rsp_src.enq(FromLoad);
                load_meta_q.enq(LoadMeta { loc: loc, next: has_next_piece, deallocate: deallocate, st: st, orig_token: orig_token });
                // let tile = mem.read(set, loc.frame);
                // let out_rank = tile.st;

                // Check if weve processed all entries for this token
                // let next_set = set + 1;
                // if (has_next_piece matches tagged Valid .next_loc) begin
                //     next_set = next_loc.set;
                //     load_token <= tagged Valid LoadState { loc: next_loc, deallocate: deallocate, st: st, orig_token: orig_token };
                // end else begin
                //     load_token <= tagged Invalid;
                //     out_rank = rank + st;
                //     if (deallocate) begin
                //         deallocate_reg <= tagged Valid truncate(orig_token); // used to reset the token_counter head
                //     end
                // end
                
                // receive_send_data_output <= tagged Valid tuple2(tagged Tag_Tile tile.t, out_rank);
                // if (deallocate && coords == loc.coords && set != next_set) begin
                //     free_list.freeSet(set); 
                // end
            end

        end
    endrule
    rule continue_load_tile_enq (continue_load_tile_request_data matches tagged Valid .continue_load_tile_request_info);
        request_data[tpl_1(continue_load_tile_request_info)].enq(tagged Tag_Request_Data tpl_2(continue_load_tile_request_info));
        $display("Sending request for data in direction %d at PMU %d, %d", tpl_1(continue_load_tile_request_info), coords.x, coords.y);
    endrule
    rule deallocate_token (initialized &&& deallocate_reg matches tagged Valid .token_id);
        first_entry.upd(token_id, tagged Invalid);
        token_complete.upd(token_id, False);
    endrule

    // ============================================================================
    // End Token and Error Rules
    // ============================================================================

    rule store_end_token (initialized &&& data_in.first matches tagged Tag_EndToken .et &&& token_out.notFull);
        $display("End token received in store at PMU %d, %d", coords.x, coords.y);
        data_in.deq;
        token_out.enq(tagged Tag_EndToken et);
    endrule

    rule store_error (initialized &&& data_in.first matches tagged Tag_Instruction .ip);
        $display("[ERROR]: Instruction received in data input"); // TODO: Should be able to accept incoming config
        $finish(0);
    endrule

    rule start_load_error (initialized &&& token_in.first matches tagged Tag_Instruction .ip);
        $display("[ERROR]: Instruction received in token input");
        $finish(0);
    endrule

    rule start_load_end_token (initialized &&& !isValid(load_token) &&& !data_request_in_flight &&& !isValid(receive_send_data_output) &&& token_in.first matches tagged Tag_EndToken .et);
        $display("End token received in start load at PMU %d, %d", coords.x, coords.y);
        token_in.deq;
        // Print state of memory at end of stream
        for (Integer i = 0; i < valueOf(SETS); i = i + 1) begin
            if (!free_list.isSetFree(fromInteger(i))) begin
                $display("[MEMORY USAGE]: Set %d: %d frames used", i, usage_tracker.getCount(fromInteger(i)));
            end else begin
                $display("[MEMORY USAGE]: Set %d: No frames used", i);
            end
        end
        data_out.enq(tagged Tag_EndToken et);
    endrule

    // ============================================================================
    // Initialization and Cycle Counting Rules
    // ============================================================================

    rule initialization (!initialized);
        first_entry.upd(first_entry_initialized_index, tagged Invalid);
        token_complete.upd(first_entry_initialized_index, False);
        if (first_entry_initialized_index == fromInteger(valueOf(MAX_ENTRIES) - 1)) begin
            initialized <= True; 
        end else begin
            first_entry_initialized_index <= first_entry_initialized_index + 1;
        end
    endrule

    rule cycle_counter (initialized);
        cycle_count <= cycle_count + 1;
    endrule


    `include "Macros.bsv"
    `UNROLL_4(RULE_SEND_SPACE_RESPONSE_NO)
    `UNROLL_4(RULE_SEND_DEALLOC)
    `UNROLL_4(RULE_ORIGINAL_REQUEST_NEXT_FREE)

    // ============================================================================
    // Methods
    // ============================================================================

    method Action put_data(ChannelMessage msg);
        data_in.enq(msg);
    endmethod
    method ActionValue#(ChannelMessage) get_token();
        token_out.deq;
        return token_out.first;
    endmethod
    method Action put_token(ChannelMessage msg);
        token_in.enq(msg);
    endmethod
    method ActionValue#(ChannelMessage) get_data();
        data_out.deq;
        return data_out.first;
    endmethod
    method Int#(32) get_cycle_count();
        return unpack(cycle_count);
    endmethod
    interface Operation_IFC operation;
        method Action put(Int#(32) i, ChannelMessage msg); // i = 0 for data, 1 for token
            if (i == 0) begin
                data_in.enq(msg);
            end else begin
                token_in.enq(msg);
            end
        endmethod

        method ActionValue#(ChannelMessage) get(Int#(32) i); // i = 0 for token, 1 for data
            ChannelMessage msg;
            if (i == 0) begin
                msg = token_out.first;
                token_out.deq;
            end else begin
                msg = data_out.first;
                data_out.deq;
            end
            return msg;
        endmethod
    endinterface

endmodule

endpackage