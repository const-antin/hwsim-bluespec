#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

void add_tile_c(uint32_t* resultptr, uint32_t a[], uint32_t b[], int tile_size) {
    for (int i = 0; i < tile_size; ++i) {
        for (int j = 0; j < tile_size; ++j) {
            resultptr[i * tile_size + j] += a[i * tile_size + j] + b[i * tile_size + j];
        }
    }
}

void sub_tile_c(uint32_t* resultptr, uint32_t a[], uint32_t b[], int tile_size) {
    for (int i = 0; i < tile_size; ++i) {
        for (int j = 0; j < tile_size; ++j) {
            resultptr[i * tile_size + j] -= a[i * tile_size + j] + b[i * tile_size + j];
        }
    }
}

void mul_tile_c(uint32_t* resultptr, uint32_t a[], uint32_t b[], int tile_size) {
    for (int i = 0; i < tile_size; ++i) {
        for (int j = 0; j < tile_size; ++j) {
            resultptr[i * tile_size + j] *= a[i * tile_size + j] * b[i * tile_size + j];
        }
    }
}

void div_tile_c(uint32_t* resultptr, uint32_t a[], uint32_t b[], int tile_size) {
    for (int i = 0; i < tile_size; ++i) {
        for (int j = 0; j < tile_size; ++j) {
            resultptr[i * tile_size + j] /= a[i * tile_size + j] / b[i * tile_size + j];
        }
    }
}

// Flattened vectors: row-major
void matmul_t_tile_c(uint32_t* resultptr, uint32_t a[], uint32_t b[], int tile_size) {
    for (int i = 0; i < tile_size; ++i) {
        for (int j = 0; j < tile_size; ++j) {
            for (int k = 0; k < tile_size; ++k) {
                resultptr[i * tile_size + j] += a[i * tile_size + k] * b[j * tile_size + k];
            }
        }
    }
    return;
}

#ifdef __cplusplus
}
#endif

