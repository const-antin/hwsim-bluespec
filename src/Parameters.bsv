package Parameters;

typedef 8 NUM_PCUS;
typedef 8 NUM_PMUS;

typedef 4 NUM_INPUTS_PER_PCU;
typedef 4 NUM_OUTPUTS_PER_PCU;
typedef 4 NUM_INPUTS_PER_STAGE;
typedef 4 NUM_OUTPUTS_PER_STAGE;
typedef 4 NUM_INPUTS_PER_PMU;
typedef 4 NUM_OUTPUTS_PER_PMU;

typedef 4 NUM_STAGES;

typedef 8 FRAMES_PER_SET;
typedef Bit#(TLog#(FRAMES_PER_SET)) FRAMES_PER_SET_LOG;
typedef 128 SETS;
typedef Bit#(TLog#(SETS)) SETS_LOG;
typedef TMul#(FRAMES_PER_SET, SETS) MAX_ENTRIES;

// The ramulator context does not return requests in order. Therefore, we need a reorder buffer
// 
typedef 64 RAMULATOR_REORDER_WINDOW_SIZE;
typedef 0 RAMULATOR_PRINT_BUBBLES; // 0: no printing, 1: print bubbles

endpackage