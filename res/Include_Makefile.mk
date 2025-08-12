# ================================================================
# BSV/Verilog build environment with optional BDPI support
# FAST BUILD VERSION
# ================================================================
TUTORIAL ?= .
RESOURCES_DIR ?= $(TUTORIAL)/res
TOPLANG ?= BSV
ifeq ($(TOPLANG),BSV)
SRC_EXT=bsv
else ifeq ($(TOPLANG),BH)
SRC_EXT=bs
else
SRC_EXT=TOPLANG_NOT_DEFINED
endif

TOPFILE ?= src/Top.$(SRC_EXT)
TOPMODULE ?= mkTop
NPROC := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# ================================================================
# BUILD MODE CONFIGURATIONS
# ================================================================

# FASTEST MODE (for rapid iteration)
BSC_COMP_FLAGS_FASTEST = -aggressive-conditions -no-warn-action-shadowing -show-range-conflict \
	-parallel-sim-link $(NPROC) -cpp +RTS -K2G -RTS -Xc "lm" \
	-steps-max-intervals 10000000

BSC_LINK_FLAGS_FASTEST = -Xc "lm" -Xl "-fuse-ld=lld" +RTS -Ksize -RTS

# FAST MODE (recommended for development)
BSC_COMP_FLAGS_FAST = -keep-fires -aggressive-conditions -no-warn-action-shadowing \
	-parallel-sim-link $(NPROC) -cpp +RTS -K2G -RTS -Xc "lm" \
	-steps-max-intervals 10000000

BSC_LINK_FLAGS_FAST = -keep-fires -Xc "lm" -Xl "-fuse-ld=lld" +RTS -Ksize -RTS

# DEBUG MODE (your original flags - slow but full featured)
BSC_COMP_FLAGS_DEBUG = -keep-fires -aggressive-conditions -no-warn-action-shadowing \
	-check-assert -parallel-sim-link $(NPROC) -cpp +RTS -K2G -RTS \
	-show-range-conflict -show-schedule -Xc "lm" -steps-max-intervals 10000000 \
	-v -show-stats -sched-dot +RTS -Ksize -RTS

BSC_LINK_FLAGS_DEBUG = -keep-fires -Xc "lm" -show-stats -Xl "-fuse-ld=lld" 

# DEFAULT TO FAST MODE
BSC_COMP_FLAGS ?= $(BSC_COMP_FLAGS_FAST)
BSC_LINK_FLAGS ?= $(BSC_LINK_FLAGS_FAST)

BSC_PATHS = -p $(BSC_PATH1)src:$(RESOURCES_DIR):+
V_SIM ?= iverilog

# ================================================================
# QUICK BUILD TARGETS
# ================================================================

.PHONY: lightning
lightning: BSC_COMP_FLAGS = $(BSC_COMP_FLAGS_FASTEST) -v 
lightning: BSC_LINK_FLAGS = $(BSC_LINK_FLAGS_FASTEST) -v 
lightning: $(info === LIGHTNING MODE: Ultra-fast build ===)
lightning: b_all

.PHONY: dev  
dev: BSC_COMP_FLAGS = $(BSC_COMP_FLAGS_FAST)
dev: BSC_LINK_FLAGS = $(BSC_LINK_FLAGS_FAST)
dev: $(info === DEV MODE: Fast development build ===)
dev: b_all

.PHONY: debug
debug: BSC_COMP_FLAGS = $(BSC_COMP_FLAGS_DEBUG)
debug: BSC_LINK_FLAGS = $(BSC_LINK_FLAGS_DEBUG)
debug: $(info === DEBUG MODE: Full debugging (slow) ===)
debug: b_all

# Make 'dev' the default
.PHONY: default
default: dev

# ================================================================
# Bluesim
# ================================================================
B_SIM_DIRS = -simdir build_b_sim -bdir build_b_sim -info-dir build_b_sim
B_SIM_EXE = $(TOPMODULE)_b_sim

.PHONY: b_all
b_all: b_compile b_link b_sim

.PHONY: b_compile
b_compile:
	mkdir -p build_b_sim
	@echo Compiling for Bluesim ...
	bsc -u -sim $(B_SIM_DIRS) $(BSC_COMP_FLAGS) $(BSC_PATHS) -g $(TOPMODULE) $(TOPFILE)
	@echo Compiling for Bluesim finished

.PHONY: b_link
b_link: $(BDPI_OBJ)
	@echo Linking for Bluesim ...
	bsc -e $(TOPMODULE) -sim -o $(B_SIM_EXE) $(B_SIM_DIRS) $(BSC_LINK_FLAGS) $(BSC_PATHS) $(BDPI_OBJ)
	@echo Linking for Bluesim finished

.PHONY: b_sim
b_sim:
	@echo Bluesim simulation ...
	LD_LIBRARY_PATH=. ./$(B_SIM_EXE)
	@echo Bluesim simulation finished

.PHONY: b_sim_vcd
b_sim_vcd:
	@echo Bluesim simulation and dumping VCD in dump.vcd ...
	LD_LIBRARY_PATH=. ./$(B_SIM_EXE) -V
	@echo Bluesim simulation and dumping VCD in dump.vcd finished

# ================================================================
# CONVENIENCE TARGETS
# ================================================================

# Quick compile and run
.PHONY: run
run: dev

# Ultra-quick test iteration
.PHONY: test
test: lightning

# Build and run immediately  
.PHONY: go
go: lightning
	@echo "Running simulation..."
	LD_LIBRARY_PATH=. ./$(B_SIM_EXE)

# Time the build to measure improvements
.PHONY: time-build
time-build:
	@echo "Timing build..."
	time $(MAKE) clean lightning

# ================================================================
# Verilog
# ================================================================
V_DIRS = -vdir verilog_RTL -bdir build_v -info-dir build_v
V_SIM_EXE = $(TOPMODULE)_v_sim

.PHONY: v_all
v_all: v_compile v_link v_sim

.PHONY: v_compile
v_compile:
	mkdir -p build_v
	mkdir -p verilog_RTL
	@echo Compiling for Verilog ...
	bsc -u -verilog $(V_DIRS) $(BSC_COMP_FLAGS) $(BSC_PATHS) -g $(TOPMODULE) $(TOPFILE)
	@echo Compiling for Verilog finished

.PHONY: v_link
v_link:
	@echo Linking for Verilog sim ...
	bsc -e $(TOPMODULE) -verilog -o ./$(V_SIM_EXE) $(V_DIRS) -vsim $(V_SIM) verilog_RTL/$(TOPMODULE).v
	@echo Linking for Verilog sim finished

.PHONY: v_sim
v_sim:
	@echo Verilog simulation...
	./$(V_SIM_EXE)
	@echo Verilog simulation finished

.PHONY: v_sim_vcd
v_sim_vcd:
	@echo Verilog simulation and dumping VCD in dump.vcd ...
	./$(V_SIM_EXE) +bscvcd
	@echo Verilog simulation and dumping VCD in dump.vcd finished

# ================================================================
# BDPI Support (static object compilation)
# ================================================================
ifeq ($(BDPI_C_SRC),)
# No BDPI C source specified, do nothing
else
$(BDPI_OBJ): $(BDPI_C_SRC)
	@echo Compiling BDPI C source $(BDPI_C_SRC) to object $(BDPI_OBJ)...
	gcc -c $(BDPI_C_SRC) -o $(BDPI_OBJ)
	@echo BDPI object built: $(BDPI_OBJ)
endif

# ================================================================
# Cleanup
# ================================================================
.PHONY: clean
clean:
	rm -f build_b_sim/* build_v/* *~ src/*~ $(BDPI_OBJ)

.PHONY: full_clean
full_clean:
	rm -rf build_b_sim build_v verilog_RTL *~ src/*~ $(BDPI_OBJ)
	rm -f *$(TOPMODULE)* *.vcd

# ================================================================
# HELP
# ================================================================
.PHONY: help
help:
	@echo "Bluespec Build Targets (fastest to slowest):"
	@echo ""
	@echo "DEVELOPMENT (use these):"
	@echo "  lightning    - Ultra-fast build (minimal features)"
	@echo "  dev          - Fast development build (DEFAULT)"
	@echo "  test         - Same as lightning"
	@echo "  go           - Lightning build + run simulation"
	@echo "  run          - Same as dev"
	@echo ""
	@echo "DEBUGGING:"
	@echo "  debug        - Full debugging build (slow, all features)"
	@echo ""  
	@echo "ORIGINAL TARGETS:"
	@echo "  b_all        - Full Bluesim build (uses current mode)"
	@echo "  v_all        - Full Verilog build"
	@echo "  b_sim        - Just run simulation"
	@echo "  b_sim_vcd    - Run simulation with VCD dump"
	@echo ""
	@echo "UTILITIES:"
	@echo "  time-build   - Time the build to measure performance"
	@echo "  clean        - Clean build files"
	@echo "  full_clean   - Clean everything"
	@echo "  help         - Show this help"
	@echo ""
	@echo "EXAMPLES:"
	@echo "  make              # Fast development build"
	@echo "  make go           # Ultra-fast build and run"
	@echo "  make debug        # When you need full debugging"
	@echo "  make time-build   # Measure build performance"