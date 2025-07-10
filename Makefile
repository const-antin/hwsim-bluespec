###  -*-Makefile-*-
# Copyright (c) 2018-2020 Bluespec, Inc. All Rights Reserved

# ================================================================

# Optional: override default BDPI C source and object
BDPI_C_SRC ?= dpi/matmul_tile.c
BDPI_OBJ     ?= dpi/matmul_tile.o

include ./res/Include_Makefile.mk