# ================================================================
# BSV/Verilog build environment with optional BDPI support
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

BSC_COMP_FLAGS += -keep-fires -aggressive-conditions -no-warn-action-shadowing -check-assert -cpp \
	+RTS -K128M -RTS -show-range-conflict -show-schedule -Xc "lm" -steps-max-intervals 10000000 -v -show-stats -sched-dot

BSC_LINK_FLAGS += -keep-fires -Xc "lm" -show-stats
BSC_PATHS = -p $(BSC_PATH1)src:$(RESOURCES_DIR):+

V_SIM ?= iverilog

# ================================================================
# Bluesim

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
# Verilog

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

.PHONY: clean
clean:
	rm -f build_b_sim/* build_v/* *~ src/*~ $(BDPI_OBJ)

.PHONY: full_clean
full_clean:
	rm -rf build_b_sim build_v verilog_RTL *~ src/*~ $(BDPI_OBJ)
	rm -f *$(TOPMODULE)* *.vcd