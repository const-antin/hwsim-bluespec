package InstantiateGrid;

import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import Types::*;
import Parameters::*;
import PMU::*;

typedef 1 RANK;

// Module version that returns the PMU grid
module mkPMUGrid (Vector#(NUM_PMUS, Vector#(NUM_PMUS, PMU_IFC)));
    // Create shared FIFOs for the mesh
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_request_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_request_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_send_data <- replicateM(replicateM(mkGFIFOF(True, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_send_data <- replicateM(replicateM(mkGFIFOF(True, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_request_space <- replicateM(replicateM(mkPipelineFIFOF));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_request_space <- replicateM(replicateM(mkPipelineFIFOF));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_send_space <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_send_space <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_send_dealloc <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_send_dealloc <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) ns_send_update_pointer <- replicateM(replicateM(mkGFIFOF(True, True)));
    Vector#(TAdd#(NUM_PMUS, 1), Vector#(NUM_PMUS, FIFOF#(MessageType))) sn_send_update_pointer <- replicateM(replicateM(mkGFIFOF(True, True)));

    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_request_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_request_data <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_send_data <- replicateM(replicateM(mkGFIFOF(True, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_send_data <- replicateM(replicateM(mkGFIFOF(True, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_request_space <- replicateM(replicateM(mkPipelineFIFOF));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_request_space <- replicateM(replicateM(mkPipelineFIFOF));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_send_space <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_send_space <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_send_dealloc <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_send_dealloc <- replicateM(replicateM(mkGFIFOF(False, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) ew_send_update_pointer <- replicateM(replicateM(mkGFIFOF(True, True)));
    Vector#(NUM_PMUS, Vector#(TAdd#(NUM_PMUS, 1), FIFOF#(MessageType))) we_send_update_pointer <- replicateM(replicateM(mkGFIFOF(True, True)));
    
    // Instantiate the PMUs
    Vector#(NUM_PMUS, Vector#(NUM_PMUS, PMU_IFC)) pmus = replicate(newVector());

    for (Integer i = 0; i < valueOf(NUM_PMUS); i = i + 1) begin
        for (Integer j = 0; j < valueOf(NUM_PMUS); j = j + 1) begin
            Vector#(4, FIFOF#(MessageType)) request_data = newVector();
            request_data[0] = sn_request_data[i][j];     // North
            request_data[1] = ns_request_data[i + 1][j]; // South
            request_data[2] = ew_request_data[i][j];     // West
            request_data[3] = we_request_data[i][j + 1]; // East

            Vector#(4, FIFOF#(MessageType)) receive_request_data = newVector();
            receive_request_data[0] = ns_request_data[i][j];     // North
            receive_request_data[1] = sn_request_data[i + 1][j]; // South
            receive_request_data[2] = we_request_data[i][j];     // West
            receive_request_data[3] = ew_request_data[i][j + 1]; // East

            Vector#(4, FIFOF#(MessageType)) send_data = newVector();
            send_data[0] = sn_send_data[i][j];
            send_data[1] = ns_send_data[i + 1][j];
            send_data[2] = ew_send_data[i][j];
            send_data[3] = we_send_data[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) receive_send_data = newVector();
            receive_send_data[0] = ns_send_data[i][j];
            receive_send_data[1] = sn_send_data[i + 1][j];
            receive_send_data[2] = we_send_data[i][j];
            receive_send_data[3] = ew_send_data[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) request_space = newVector();
            request_space[0] = sn_request_space[i][j];     // North
            request_space[1] = ns_request_space[i + 1][j]; // South
            request_space[2] = ew_request_space[i][j];     // West
            request_space[3] = we_request_space[i][j + 1]; // East

            Vector#(4, FIFOF#(MessageType)) receive_request_space = newVector();
            receive_request_space[0] = ns_request_space[i][j];     // North
            receive_request_space[1] = sn_request_space[i + 1][j]; // South
            receive_request_space[2] = we_request_space[i][j];     // West
            receive_request_space[3] = ew_request_space[i][j + 1]; // East

            Vector#(4, FIFOF#(MessageType)) send_space = newVector();
            send_space[0] = sn_send_space[i][j];
            send_space[1] = ns_send_space[i + 1][j];
            send_space[2] = ew_send_space[i][j];
            send_space[3] = we_send_space[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) receive_send_space = newVector();
            receive_send_space[0] = ns_send_space[i][j];
            receive_send_space[1] = sn_send_space[i + 1][j];
            receive_send_space[2] = we_send_space[i][j];
            receive_send_space[3] = ew_send_space[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) send_dealloc = newVector();
            send_dealloc[0] = sn_send_dealloc[i][j];
            send_dealloc[1] = ns_send_dealloc[i + 1][j];
            send_dealloc[2] = ew_send_dealloc[i][j];
            send_dealloc[3] = we_send_dealloc[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) receive_send_dealloc = newVector();
            receive_send_dealloc[0] = ns_send_dealloc[i][j];
            receive_send_dealloc[1] = sn_send_dealloc[i + 1][j];
            receive_send_dealloc[2] = we_send_dealloc[i][j];
            receive_send_dealloc[3] = ew_send_dealloc[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) send_update_pointer = newVector();
            send_update_pointer[0] = sn_send_update_pointer[i][j];
            send_update_pointer[1] = ns_send_update_pointer[i + 1][j];
            send_update_pointer[2] = ew_send_update_pointer[i][j];
            send_update_pointer[3] = we_send_update_pointer[i][j + 1];

            Vector#(4, FIFOF#(MessageType)) receive_send_update_pointer = newVector();
            receive_send_update_pointer[0] = ns_send_update_pointer[i][j];
            receive_send_update_pointer[1] = sn_send_update_pointer[i + 1][j];
            receive_send_update_pointer[2] = we_send_update_pointer[i][j];
            receive_send_update_pointer[3] = ew_send_update_pointer[i][j + 1];

            pmus[i][j] <- mkPMU(
                fromInteger(valueOf(RANK)), // rank  
                Coords { x: fromInteger(j), y: fromInteger(i) }, // coords
                request_data,
                receive_request_data,
                send_data,
                receive_send_data,
                request_space,
                receive_request_space,
                send_space,
                receive_send_space,
                send_dealloc,
                receive_send_dealloc,
                send_update_pointer,
                receive_send_update_pointer
            );
        end
    end

    return pmus;
endmodule

endpackage
