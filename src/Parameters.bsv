package Parameters;

typedef 8 NUM_PCUS;
typedef 3 NUM_PMUS; // This is side of a square -> really NUM_PMUS^2 = NUM_PMUS

typedef 4 NUM_INPUTS_PER_PCU;
typedef 4 NUM_OUTPUTS_PER_PCU;
typedef 4 NUM_INPUTS_PER_STAGE;
typedef 4 NUM_OUTPUTS_PER_STAGE;
typedef 4 NUM_INPUTS_PER_PMU;
typedef 4 NUM_OUTPUTS_PER_PMU;

typedef 4 NUM_STAGES;

typedef 2 FRAMES_PER_SET;
typedef TMax#(1, TLog#(FRAMES_PER_SET)) FRAMES_PER_SET_LOG;
typedef UInt#(FRAMES_PER_SET_LOG) FRAME_INDEX;
typedef 4 SETS;
typedef TLog#(SETS) SETS_LOG;
typedef UInt#(SETS_LOG) SET_INDEX;
typedef TMul#(FRAMES_PER_SET, SETS) MAX_ENTRIES;
typedef Bit#(TLog#(MAX_ENTRIES)) TokID;

endpackage