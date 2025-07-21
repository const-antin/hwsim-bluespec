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

typedef 2 FRAMES_PER_SET;
typedef TLog#(FRAMES_PER_SET) FRAMES_PER_SET_LOG;
typedef Bit#(FRAMES_PER_SET_LOG) FRAME_INDEX;
typedef 16 SETS;
typedef TLog#(SETS) SETS_LOG;
typedef Bit#(SETS_LOG) SET_INDEX;
typedef TMul#(FRAMES_PER_SET, SETS) MAX_ENTRIES;

endpackage