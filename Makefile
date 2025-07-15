###  -*-Makefile-*-
# Copyright (c) 2018-2020 Bluespec, Inc. All Rights Reserved

# ================================================================

# Optional: override default BDPI C source and object
BDPI_C_SRC ?= dpi/matmul_tile.c
BDPI_OBJ     ?= dpi/matmul_tile.o

# Add SMU directory to search path
BSC_PATH1 = src/SMU:

include ./res/Include_Makefile.mk