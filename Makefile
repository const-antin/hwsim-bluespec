###  -*-Makefile-*-
# Copyright (c) 2018-2020 Bluespec, Inc. All Rights Reserved

# ================================================================

# Optional: override default BDPI C source and object
BDPI_C_SRC ?= dpi/matmul_tile.c dpi/ramulator_wrapper.cpp
BDPI_OBJ   ?= $(BDPI_C_SRC:.c=.o)

# Add SMU directory to search path
BSC_PATH1 = src/SMU:

include ./res/Include_Makefile.mk