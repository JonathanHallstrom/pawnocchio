#include "simd.h"
#include <immintrin.h>
#include <stdint.h>

#ifdef __AVX512F__


i32Vec dpbusd(i32Vec sum, u8Vec u1, i8Vec i1) { return _mm512_dpbusd_epi32(sum, u1, i1); }
u8Vec packus(i16Vec a, i16Vec b) { return _mm512_packus_epi16(a, b); }
i16Vec mulhi(i16Vec a, i16Vec b) { return _mm512_mulhi_epi16(a, b); }

void dpbusd_ptr(i32Vec *sum, const u8Vec *u1, const i8Vec *i1) { *sum = _mm512_dpbusd_epi32(*sum, *u1, *i1); }
void packus_ptr(const i16Vec *a, const i16Vec *b, u8Vec *out) { *out = _mm512_packus_epi16(*a, *b); }
void mulhi_ptr(const i16Vec *a, const i16Vec *b, i16Vec *out) { *out = _mm512_mulhi_epi16(*a, *b); }

#endif
