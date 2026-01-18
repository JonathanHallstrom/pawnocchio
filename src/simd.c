#include "simd.h"
#include <immintrin.h>
#include <stdint.h>

#define __AVX512F__
#ifdef __AVX512F__

// typedef int32_t i32Vec __attribute__((vector_size(64)));
// typedef int16_t i16Vec __attribute__((vector_size(64)));
// typedef uint8_t u8Vec __attribute__((vector_size(64)));
// typedef int8_t i8Vec __attribute__((vector_size(64)));
typedef __m512i Vec;

Vec dpbusd(Vec sum, Vec u1, Vec i1) { return _mm512_dpbusd_epi32(sum, u1, i1); }

Vec packus(Vec a, Vec b) { return _mm512_packus_epi16(a, b); }

Vec mulhi(Vec a, Vec b) { return _mm512_mulhi_epi16(a, b); }

#endif
