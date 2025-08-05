// TODO: Make everything work in fifo order. I think this should immediately work as long as I emit the token earlier. 
    // I already have the logic necessary to make sure i don't read data that hasn't been stored (untested)

// TODO: Replace loop with find
// TODO: Remove memory size dependency on tile size, should just have banks be as large as possible
// TODO: Swap registers for SRAM
// TODO: rank shouldnt be a parameter, should be stored in a reg and parsed from a config input
// TODO: Technically having the entry ports to be guarded might be a problem, because if I want to enqueue only in one direction, but another blocks, thats wrong.
// TODO: Fair aribitration between directions data is sent, currently prioritizes north, then south, then west, then east.

package PMU;

import FIFO::*;
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

    FIFO#(ChannelMessage) data_in <- mkFIFO;      // Values come in here
    FIFO#(ChannelMessage) token_out <- mkFIFO;    // Generated tokens go out here
    FIFO#(ChannelMessage) token_in <- mkFIFO;     // Tokens come back in here
    FIFO#(ChannelMessage) data_out <- mkFIFO;     // Retrieved values go out here

    // initialization and cycle count
    Reg#(Bit#(32)) cycle_count <- mkReg(0);
    Reg#(Bool) initialized <- mkReg(False);
    Reg#(Bit#(TLog#(MAX_ENTRIES))) first_entry_initialized_index <- mkReg(0);

    ConfigReg#(Bit#(TLog#(MAX_ENTRIES))) token_counter <- mkConfigReg(0);

    // storage usage tracking
    BankedMemory_IFC mem <- mkBankedMemory;
    SetFreeList_IFC free_list <- mkSetFreeList;
    SetUsageTracker_IFC usage_tracker <- mkSetUsageTracker;
    Reg#(Maybe#(StorageAddr)) curr_loc <- mkReg(tagged Invalid);
    Reg#(Maybe#(StorageAddr)) prev_loc <- mkReg(tagged Invalid);
    ConfigReg#(Maybe#(StorageAddr)) next_free_set <- mkConfigReg(tagged Invalid);

    // storage chain logic
    RegFile#(Bit#(TLog#(MAX_ENTRIES)), Maybe#(StorageAddr)) first_entry <- mkRegFileWCF(0, fromInteger(valueOf(MAX_ENTRIES) - 1));    
    RegFile#(Bit#(TLog#(MAX_ENTRIES)), Bool) token_complete <- mkRegFileWCF(0, fromInteger(valueOf(MAX_ENTRIES) - 1));
    Vector#(MAX_ENTRIES, ConfigReg#(Maybe#(StorageAddr))) next_table <- replicateM(mkConfigReg(tagged Invalid));
    Reg#(StorageAddr) prev_stored <- mkReg(StorageAddr { set: 0, frame: 0, x: 0, y: 0 });

    // load and deallocate registers
    ConfigReg#(Maybe#(LoadState)) load_token <- mkConfigReg(tagged Invalid);
    ConfigReg#(Maybe#(Bit#(TLog#(MAX_ENTRIES)))) deallocate_reg <- mkConfigReg(tagged Invalid);

    // In flight trackers
    Reg#(Bool) space_request_in_flight <- mkReg(False);
    Reg#(Int#(32)) num_space_requests_in_flight <- mkReg(0);
    Reg#(Bool) data_request_in_flight <- mkReg(False);

    // Round robin counters
    Reg#(Bit#(32)) space_round_robin_counter <- mkReg(0);
    Reg#(Bit#(32)) dealloc_round_robin_counter <- mkReg(0);
    Reg#(Bit#(32)) receive_send_data_round_robin_counter_store <- mkReg(0);
    Reg#(Bit#(32)) receive_send_data_round_robin_counter_load <- mkReg(0);
    Reg#(Bit#(32)) receive_request_data_round_robin_counter <- mkReg(0);
    Reg#(Bit#(32)) receive_send_update_pointer_round_robin_counter <- mkReg(0);

    Wire#(Maybe#(Bit#(2))) store_direction <- mkDWire(tagged Invalid);

    ConfigReg#(Bit#(32)) num_stored_to_current_frame <- mkConfigReg(0);

    // ============================================================================
    // Rule Orderings
    // ============================================================================

    (* execution_order = "cycle_counter, round_robin_space_request, receive_send_space, store_tile, next_free, continue_load_tile" *)
    (* execution_order = "cycle_counter, start_load_tile, receive_send_data" *)
    (* execution_order = "receive_deallocate, receive_request_data, next_free, continue_load_tile" *)
    (* execution_order = "receive_send_update_pointer, receive_send_data" *)
    (* execution_order = "receive_send_update_pointer, store_tile" *)
    (* descending_urgency = "deallocate_token, store_tile, round_robin_space_request" *)
    (* descending_urgency = "store_tile, receive_send_data" *)
    (* descending_urgency = "store_tile, receive_request_data" *)
    (* descending_urgency = "space_request_no, round_robin_space_request" *)
    (* conflict_free = "receive_send_data, start_load_end_token" *)
    (* conflict_free = "receive_send_data, continue_load_tile" *)

    // ============================================================================
    // Main Logic Rules
    // ============================================================================

    rule deallocate_token (initialized &&& deallocate_reg matches tagged Valid .token_id);
        first_entry.upd(token_id, tagged Invalid);
        token_complete.upd(token_id, False);
        deallocate_reg <= tagged Invalid;
    endrule

    rule space_request_no (initialized &&& (!isValid(next_free_set) || space_request_in_flight || (isValid(next_free_set) &&& (next_free_set.Valid.x != coords.x || next_free_set.Valid.y != coords.y))));
        function notEmptyFunc(x) = tpl_1(x).notEmpty && tpl_2(x).notFull; 
        Vector#(4, Bool) has_data = map(notEmptyFunc, zip(receive_request_space, send_space));
        
        for (Bit#(32) i = 0; i < 4; i = i + 1) begin
            if (has_data[i]) begin
                receive_request_space[i].deq;
                send_space[i].enq(tagged Tag_FreeSpaceNo);
            end
        end
    endrule

    rule round_robin_space_request (initialized &&& isValid(next_free_set) &&& next_free_set.Valid.x == coords.x &&& next_free_set.Valid.y == coords.y);
        function notEmptyFunc(x) = tpl_1(x).notEmpty && tpl_2(x).notFull; 
        Vector#(4, Bool) has_data = map(notEmptyFunc, zip(receive_request_space, send_space));
        Maybe#(Bit#(2)) m_idx = roundRobinFind(space_round_robin_counter, has_data);
        if (m_idx matches tagged Valid .idx) begin
            receive_request_space[idx].deq;
            send_space[idx].enq(tagged Tag_FreeSpaceYes StorageAddr { set: next_free_set.Valid.set, frame: 0, x: coords.x, y: coords.y });
            next_free_set <= tagged Invalid;
            space_round_robin_counter <= (zeroExtend(idx) + 1) % 4;
        end
    endrule

    rule receive_deallocate (initialized);
        function notEmptyFunc(x) = x.notEmpty;
        Vector#(4, Bool) has_data = map(notEmptyFunc, receive_send_dealloc);
        Maybe#(Bit#(2)) m_idx = roundRobinFind(dealloc_round_robin_counter, has_data);
        if (m_idx matches tagged Valid .idx) begin
            receive_send_dealloc[idx].deq;
            let loc = receive_send_dealloc[idx].first.Tag_Deallocate;
            free_list.freeSet(loc.set);
            dealloc_round_robin_counter <= (zeroExtend(idx) + 1) % 4;
        end
    endrule

    rule receive_send_space (initialized && space_request_in_flight);
        function notEmptyFunc(x) = x.notEmpty;
        Vector#(4, Bool) has_data = map(notEmptyFunc, receive_send_space);
        
        Int#(32) num_responses_received = 0;
        Int#(32) num_yesses = 0;
        
        for (Integer i = 0; i < 4; i = i + 1) begin
            if (has_data[i]) begin
                receive_send_space[i].deq;
                num_responses_received = num_responses_received + 1;
                
                if (receive_send_space[i].first matches tagged Tag_FreeSpaceYes .loc) begin
                    if (num_yesses == 0) begin
                        next_free_set <= tagged Valid loc;
                    end else begin
                        send_dealloc[i].enq(tagged Tag_Deallocate loc);
                    end
                    num_yesses = num_yesses + 1;
                end
            end
        end

        if (num_responses_received == num_space_requests_in_flight) begin
            space_request_in_flight <= False;
        end
    endrule

    rule next_free (initialized && !isValid(next_free_set) && !space_request_in_flight);
        let mset <- free_list.allocSet();
        case (mset) matches
            tagged Valid .s: begin
                next_free_set <= tagged Valid StorageAddr { set: s, frame: 0, x: coords.x, y: coords.y };
            end
            default: begin
                $display("***** Out of memory at PMU %d, %d, load token validity is %d *****", coords.x, coords.y, isValid(load_token));
                next_free_set <= tagged Invalid;
                let num_requests_sent = 0;
                if (request_space[0].notFull && coords.y > 0) begin
                    request_space[0].enq(tagged Tag_EndToken 0);
                    num_requests_sent = num_requests_sent + 1;
                end 
                if (request_space[1].notFull && coords.y < fromInteger(valueOf(NUM_PMUS) - 1)) begin
                    request_space[1].enq(tagged Tag_EndToken 0);
                    num_requests_sent = num_requests_sent + 1;  
                end 
                if (request_space[2].notFull && coords.x > 0) begin
                    request_space[2].enq(tagged Tag_EndToken 0);
                    num_requests_sent = num_requests_sent + 1;
                end
                if (request_space[3].notFull && coords.x < fromInteger(valueOf(NUM_PMUS) - 1)) begin
                    request_space[3].enq(tagged Tag_EndToken 0);
                    num_requests_sent = num_requests_sent + 1;
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
        function notEmptyAndStore(x) = x.notEmpty &&& (x.first matches tagged Tag_Store .d ? True : False);
        Vector#(4, Bool) has_store_data = map(notEmptyAndStore, receive_send_data);
        function notEmptyAndLoad(x) = data_request_in_flight &&& x.fst.notEmpty &&& (x.fst.first matches tagged Tag_Load .d ? True : False) &&& !x.snd;
        Vector#(4, Tuple2#(FIFOF#(MessageType), Bool)) paired_data = zip(receive_send_data, has_store_data);
        Vector#(4, Bool) has_load_data = map(notEmptyAndLoad, paired_data);

        Maybe#(Bit#(2)) m_idx = roundRobinFind(receive_send_data_round_robin_counter_store, has_store_data);
        if (m_idx matches tagged Valid .idx) begin
            receive_send_data[idx].deq;
            if (receive_send_data[idx].first matches tagged Tag_Store .data_with_next) begin
                let data = data_with_next.data;
                let loc = data_with_next.loc;
                mem.write(loc.set, loc.frame, data);
                if (loc.frame > 0) begin
                    let old_loc = StorageAddr { set: loc.set, frame: loc.frame - 1, x: loc.x, y: loc.y };
                    next_table[storageAddrToIndex(old_loc)] <= tagged Valid loc;
                end
                next_table[storageAddrToIndex(loc)] <= tagged Invalid;
            end
            receive_send_data_round_robin_counter_store <= (zeroExtend(idx) + 1) % 4;
        end

        Maybe#(Bit#(2)) m_idx2 = roundRobinFind(receive_send_data_round_robin_counter_load, has_load_data);
        if (m_idx2 matches tagged Valid .idx) begin
            receive_send_data[idx].deq;
            if (receive_send_data[idx].first matches tagged Tag_Load .data_with_next) begin
                let data = data_with_next.data;
                let next = data_with_next.next;
                data_request_in_flight <= False;
                let out_rank = data.st;
                if (!isValid(next)) begin
                    out_rank = rank + load_token.Valid.st;
                    load_token <= tagged Invalid;
                end else begin
                    load_token <= tagged Valid LoadState { 
                        loc: next.Valid, 
                        deallocate: load_token.Valid.deallocate, 
                        st: load_token.Valid.st, 
                        orig_token: load_token.Valid.orig_token 
                    };
                end
                data_out.enq(tagged Tag_Data tuple2(tagged Tag_Tile data.t, out_rank));
            end
            receive_send_data_round_robin_counter_load <= (zeroExtend(idx) + 1) % 4;
        end
    endrule

    rule receive_request_data (initialized);
        function notEmpty(x) = x.notEmpty;
        Vector#(4, Bool) has_data = map(notEmpty, receive_request_data);
        Maybe#(Bit#(2)) m_idx = roundRobinFind(receive_request_data_round_robin_counter, has_data);
        if (m_idx matches tagged Valid .idx) begin
            receive_request_data[idx].deq;
            if (receive_request_data[idx].first matches tagged Tag_Request_Data .request_storage_addr) begin
                let loc = request_storage_addr.loc;
                let deallocate = request_storage_addr.deallocate;
                let tile = mem.read(loc.set, loc.frame);
                let next = next_table[storageAddrToIndex(loc)];
                if (deallocate &&& (!isValid(next) || loc.set != next.Valid.set)) begin
                    free_list.freeSet(loc.set); 
                end
                send_data[idx].enq(tagged Tag_Load DataWithNext { data: tile, loc: loc, next: next });
            end
            receive_request_data_round_robin_counter <= (zeroExtend(idx) + 1) % 4;
        end
    endrule

    rule receive_send_update_pointer (initialized);
        function notEmpty(x) = x.notEmpty;
        Vector#(4, Bool) has_data = map(notEmpty, receive_send_update_pointer);
        Maybe#(Bit#(2)) m_idx = roundRobinFind(receive_send_update_pointer_round_robin_counter, has_data);
        if (m_idx matches tagged Valid .idx) begin
            receive_send_update_pointer[idx].deq;
            if (receive_send_update_pointer[idx].first matches tagged Tag_Update_Next_Table .prev_to_next) begin
                let prev = prev_to_next.prev;
                let next = prev_to_next.next;
                next_table[storageAddrToIndex(prev)] <= tagged Valid next;
            end
            receive_send_update_pointer_round_robin_counter <= (zeroExtend(idx) + 1) % 4;
        end
    endrule

    rule store_tile (initialized && (isValid(next_free_set) || isValid(curr_loc)) &&& data_in.first matches tagged Tag_Data {.tt, .st});
        data_in.deq;

        // initialization
        let tile = unwrapTile(tt);
        let {new_st, emit_token} = processStopToken(st, rank);

        SET_INDEX set;
        FRAME_INDEX frame; 
        Coords new_coords;
        Maybe#(StorageAddr) new_loc;
        if (!isValid(curr_loc)) begin
            set = next_free_set.Valid.set;
            frame = 0;
            new_coords = Coords { x: next_free_set.Valid.x, y: next_free_set.Valid.y };
            if (new_coords == coords) begin
                usage_tracker.setFrame(set, 1);
            end
            num_stored_to_current_frame <= 1;
            next_free_set <= tagged Invalid;
            new_loc = tagged Valid StorageAddr { set: next_free_set.Valid.set, frame: 1, x: next_free_set.Valid.x, y: next_free_set.Valid.y };
        end else begin
            set = curr_loc.Valid.set;
            frame = curr_loc.Valid.frame;
            new_coords = Coords { x: curr_loc.Valid.x, y: curr_loc.Valid.y };
            if (new_coords == coords) begin
                usage_tracker.incFrame(set);
            end
            let full = num_stored_to_current_frame == fromInteger(valueOf(FRAMES_PER_SET) - 1);
            num_stored_to_current_frame <= num_stored_to_current_frame + 1;
            let is_full = full || emit_token;
            new_loc = is_full ? tagged Invalid : tagged Valid StorageAddr { set: set, frame: frame + 1, x: curr_loc.Valid.x, y: curr_loc.Valid.y };
        end
        if (new_coords.x != coords.x || new_coords.y != coords.y) begin
            let neighbor_dir = getNeighborDirection(coords, new_coords);
            send_data[directionToIndex(neighbor_dir)].enq(tagged Tag_Store DataWithNext {data: TaggedTile { t: tile, st: st }, loc: StorageAddr { set: set, frame: frame, x: new_coords.x, y: new_coords.y }, next: new_loc});
        end else begin 
            mem.write(set, frame, TaggedTile { t: tile, st: st });
        end
        prev_loc <= curr_loc;
        curr_loc <= new_loc;

        // update the storage location pointer chain
        if (first_entry.sub(token_counter) matches tagged Invalid) begin
            let p = StorageAddr { set: set, frame: frame, x: new_coords.x, y: new_coords.y };
            first_entry.upd(token_counter, tagged Valid p);
            if (new_coords.x == coords.x && new_coords.y == coords.y) begin
                next_table[storageAddrToIndex(p)] <= tagged Invalid;
            end
            prev_stored <= p;
        end else begin
            let p = StorageAddr { set: set, frame: frame, x: new_coords.x, y: new_coords.y };
            Bool prev_is_local = (prev_stored.x == coords.x && prev_stored.y == coords.y);
            Bool curr_is_local = (new_coords.x == coords.x && new_coords.y == coords.y);

            if (prev_is_local && curr_is_local) begin
                let prev_index = storageAddrToIndex(prev_stored);
                let curr_index = storageAddrToIndex(p);
                if (prev_index != curr_index) begin
                    next_table[prev_index] <= tagged Valid p;      // prev points to new location
                    next_table[curr_index] <= tagged Invalid;      // new location has no next
                end else begin
                    // Same index (shouldnt happen in practice, but handle it)
                    next_table[curr_index] <= tagged Invalid; 
                end
            end else if (prev_is_local) begin
                next_table[storageAddrToIndex(prev_stored)] <= tagged Valid p;
            end else if (curr_is_local) begin
                next_table[storageAddrToIndex(p)] <= tagged Invalid;
            end

            // update pointer chain
            if (!prev_is_local && prev_stored.frame == fromInteger(valueOf(FRAMES_PER_SET) - 1)) begin
                send_update_pointer[directionToIndex(getNeighborDirection(coords, Coords { x: prev_stored.x, y: prev_stored.y }))].enq(tagged Tag_Update_Next_Table PrevToNextTag { prev: prev_stored, next: p });
            end 
            prev_stored <= p;
        end

        if (emit_token) begin
            Bit#(32) token_to_emit = zeroExtend(token_counter);
            token_complete.upd(token_counter, True);
            token_out.enq(tagged Tag_Data tuple2(tagged Tag_Ref tuple2(token_to_emit, True), new_st));
            token_counter <= token_counter + 1;
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

    rule continue_load_tile (initialized &&& load_token matches tagged Valid .load_tk_val &&& !isValid(deallocate_reg) &&& !data_request_in_flight);
        StorageAddr loc = load_tk_val.loc;
        let deallocate = load_tk_val.deallocate;
        let st = load_tk_val.st;
        let orig_token = load_tk_val.orig_token;

        Bool token_is_complete = token_complete.sub(orig_token);
        Bool has_next_piece = isValid(next_table[storageAddrToIndex(loc)]);

        if (token_is_complete || has_next_piece) begin
            let set = loc.set;
            let frame = loc.frame;
            let x = loc.x;
            let y = loc.y;
            if (coords.x != x || coords.y != y) begin
                data_request_in_flight <= True;
                let request_coords = Coords {x: x, y: y};
                request_data[directionToIndex(getNeighborDirection(coords, request_coords))].enq(tagged Tag_Request_Data RequestStorageAddr { loc: loc, deallocate: deallocate });
            end else begin 
                let tile = mem.read(set, frame);
                let out_rank = tile.st;

                // Check if weve processed all entries for this token
                let next_set = set + 1;
                if (next_table[storageAddrToIndex(loc)] matches tagged Valid .next_loc) begin
                    next_set = next_loc.set;
                    load_token <= tagged Valid LoadState { loc: next_loc, deallocate: deallocate, st: st, orig_token: orig_token };
                end else begin
                    load_token <= tagged Invalid;
                    out_rank = rank + st;
                    if (deallocate) begin
                        deallocate_reg <= tagged Valid truncate(orig_token); // used to reset the token_counter head
                    end
                end
                
                data_out.enq(tagged Tag_Data tuple2(tagged Tag_Tile tile.t, out_rank));
                if (deallocate && x == coords.x && y == coords.y) begin
                    if (set != next_set) begin
                        free_list.freeSet(set); 
                    end 
                end
            end

        end
    endrule

    // ============================================================================
    // End Token and Error Rules
    // ============================================================================

    rule store_end_token (initialized &&& data_in.first matches tagged Tag_EndToken .et);
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

    rule start_load_end_token (initialized &&& !isValid(load_token) &&& !data_request_in_flight &&& token_in.first matches tagged Tag_EndToken .et);
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

    // ============================================================================
    // Methods
    // ============================================================================

    method Action put_data(ChannelMessage msg);
        data_in.enq(msg);
    endmethod
    method ActionValue#(ChannelMessage) get_token();
        let msg = token_out.first;
        token_out.deq;
        return msg;
    endmethod
    method Action put_token(ChannelMessage msg);
        token_in.enq(msg);
    endmethod
    method ActionValue#(ChannelMessage) get_data();
        let msg = data_out.first;
        data_out.deq;
        return msg;
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