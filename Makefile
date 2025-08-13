###  -*-Makefile-*-
# Copyright (c) 2018-2020 Bluespec, Inc. All Rights Reserved

# ================================================================

# Optional: override default BDPI C source
BDPI_C_SRC ?= dpi/matmul_tile.c dpi/ramulator_wrapper.cpp

# Add SMU directory to search path
BSC_PATH1 = src/SMU:src/Interconnect:src/OffChip:src/SCU:

# ================================================================
# Ramulator flags for linking

BSC_LINK_FLAGS += -Xl "-L./ramulator2" \
		-Xl "-lramulator"    \
		-Xl "-lstdc++"       \
		-Xl "-Wl,-rpath,@loader_path/../../ramulator2"\
		-Xc++ "-I./ramulator2/ext/spdlog/include" \
		-Xc++ "-std=c++17" \
		-Xc++ "-I./ramulator2/ext/yaml-cpp/include" \
		-Xc++ "-I./ramulator2/src"

include ./res/Include_Makefile.mk

.PHONY: auto_tests

auto_tests:
	./run_tests.sh