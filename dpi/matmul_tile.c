#include <stdint.h>
#include <stdio.h>
#include <math.h>

#ifdef __cplusplus
extern "C" {
#endif

void init_target(uint32_t* target, int tile_size) {
    for (int i = 0; i < tile_size; ++i) {
        for (int j = 0; j < tile_size; ++j) {
            target[i * tile_size + j] = 0;
        }
    }
}

void print_tile(uint32_t* tile, int tile_size) {
    for (int i = 0; i < tile_size; ++i) {
        for (int j = 0; j < tile_size; ++j) {
            printf("%d ", tile[i * tile_size + j]);
        }
        printf("\n");
    }
    printf("\n");
}

void add_tile_c(uint32_t* resultptr, uint32_t a[], uint32_t b[], int tile_size) {
    init_target(resultptr, tile_size);
    for (int i = 0; i < tile_size; ++i) {
        for (int j = 0; j < tile_size; ++j) {
            resultptr[i * tile_size + j] += a[i * tile_size + j] + b[i * tile_size + j];
        }
    }
    // print_tile(resultptr, tile_size);
}

void sub_tile_c(uint32_t* resultptr, uint32_t a[], uint32_t b[], int tile_size) {
    init_target(resultptr, tile_size);
    for (int i = 0; i < tile_size; ++i) {
        for (int j = 0; j < tile_size; ++j) {
            resultptr[i * tile_size + j] -= a[i * tile_size + j] + b[i * tile_size + j];
        }
    }
    // print_tile(resultptr, tile_size);
}

void mul_tile_c(uint32_t* resultptr, uint32_t a[], uint32_t b[], int tile_size) {
    init_target(resultptr, tile_size);
    for (int i = 0; i < tile_size; ++i) {
        for (int j = 0; j < tile_size; ++j) {
            resultptr[i * tile_size + j] = a[i * tile_size + j] * b[i * tile_size + j];
        }
    }
}

void div_tile_c(uint32_t* resultptr, uint32_t a[], uint32_t b[], int tile_size) {
    init_target(resultptr, tile_size);
    for (int i = 0; i < tile_size; ++i) {
        for (int j = 0; j < tile_size; ++j) {
            resultptr[i * tile_size + j] /= a[i * tile_size + j] / b[i * tile_size + j];
        }
    }
    // print_tile(resultptr, tile_size);
}

// Flattened vectors: row-major
void matmul_t_tile_c(uint32_t* resultptr, uint32_t a[], uint32_t b[], int tile_size) {
    init_target(resultptr, tile_size);
    for (int i = 0; i < tile_size; ++i) {
        for (int j = 0; j < tile_size; ++j) {
            for (int k = 0; k < tile_size; ++k) {
                resultptr[i * tile_size + j] += a[i * tile_size + k] * b[j * tile_size + k];
            }
        }
    }
    // print_tile(resultptr, tile_size);
    return;
}

void silu_tile_c(uint32_t* resultptr, uint32_t a[], int tile_size) {
    init_target(resultptr, tile_size);
    for (int i = 0; i < tile_size; ++i) {
        for (int j = 0; j < tile_size; ++j) {
            double val = (double)a[i * tile_size + j];
            resultptr[i * tile_size + j] = (uint32_t)(val / (1.0 + exp(-val)));
        }
    }
    // printf("silu_tile_c\n");
    // print_tile(resultptr, tile_size);
    return;
}

#ifdef __cplusplus
}
#endif

