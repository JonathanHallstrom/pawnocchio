#pragma once

#include <immintrin.h>
#include <stdint.h>

#define __AVX512F__
#ifdef __AVX512F__

typedef int32_t i32Vec __attribute__((vector_size(64)));
typedef int16_t i16Vec __attribute__((vector_size(64)));
typedef uint8_t u8Vec __attribute__((vector_size(64)));
typedef int8_t i8Vec __attribute__((vector_size(64)));

i32Vec dpbusd(i32Vec sum, u8Vec u1, i8Vec i1);
u8Vec packus(i16Vec a, i16Vec b);
i16Vec mulhi(i16Vec a, i16Vec b);

void dpbusd_ptr(i32Vec *sum, const u8Vec *u1, const i8Vec *i1);
void packus_ptr(const i16Vec *a, const i16Vec *b, u8Vec *out);
void mulhi_ptr(const i16Vec *a, const i16Vec *b, i16Vec *out);

#endif
