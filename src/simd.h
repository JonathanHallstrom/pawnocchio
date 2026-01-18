#pragma once

#include <stdint.h>
#include <immintrin.h>

#define __AVX512F__
#ifdef __AVX512F__

typedef __m512i Vec;

Vec dpbusd(Vec sum, Vec u1, Vec i1);
Vec packus(Vec a, Vec b);
Vec mulhi(Vec a, Vec b);

#endif
