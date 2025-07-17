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
typedef Bit#(TLog#(FRAMES_PER_SET)) FRAMES_PER_SET_LOG;
typedef 4 SETS;
typedef Bit#(TLog#(SETS)) SETS_LOG;
typedef TMul#(FRAMES_PER_SET, SETS) MAX_ENTRIES;

endpackage