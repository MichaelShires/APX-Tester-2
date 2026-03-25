/*
 * APX Archetypal Functions for CSmith Insertion
 *
 * These functions are designed to trigger specific APX instructions.
 * They are inserted into CSmith-generated programs to test whether
 * surrounding code context causes the compiler to miss APX patterns.
 *
 * Each function is __attribute__((noinline)) to prevent the compiler
 * from inlining them into CSmith code and destroying the pattern.
 * We also test WITHOUT noinline to see if inlining breaks patterns.
 */

#ifndef APX_INSERT_H
#define APX_INSERT_H

#include <stdint.h>

/* ── CCMP: Compound conditionals ── */

__attribute__((noinline))
int apx_ccmp_and(int a, int b, int x, int y) {
    if (a > x && b < y)
        return 1;
    return 0;
}

__attribute__((noinline))
int apx_ccmp_or(int a, int b, int x, int y) {
    if (a > x || b < y)
        return 1;
    return 0;
}

__attribute__((noinline))
int apx_ccmp_range(int val, int lo, int hi) {
    if (val >= lo && val <= hi)
        return 1;
    return 0;
}

/* ── NDD CMOV: Conditional assignment ── */

__attribute__((noinline))
int apx_ndd_ternary(int a, int b, int cond) {
    return cond > 0 ? a : b;
}

__attribute__((noinline))
int apx_ndd_min(int a, int b) {
    return a < b ? a : b;
}

__attribute__((noinline))
int apx_ndd_clamp(int val, int lo, int hi) {
    int r = val;
    if (r < lo) r = lo;
    if (r > hi) r = hi;
    return r;
}

/* ── CFCMOV: Conditional memory access (requires +cf) ── */

__attribute__((noinline))
int apx_cfcmov_load(int cond, const int *ptr) {
    if (cond)
        return *ptr;
    return 0;
}

__attribute__((noinline))
void apx_cfcmov_store(int cond, int *ptr, int val) {
    if (cond)
        *ptr = val;
}

/* ── Versions WITHOUT noinline (test inlining effects) ── */

int apx_ccmp_and_inline(int a, int b, int x, int y) {
    if (a > x && b < y)
        return 1;
    return 0;
}

int apx_ndd_ternary_inline(int a, int b, int cond) {
    return cond > 0 ? a : b;
}

int apx_ccmp_range_inline(int val, int lo, int hi) {
    if (val >= lo && val <= hi)
        return 1;
    return 0;
}

/* ── Harness: call all functions using CSmith globals ── */

static volatile int apx_sink;

static void apx_harness(int a, int b, int c, int d) {
    int buf[4] = {a, b, c, d};

    /* CCMP tests */
    apx_sink += apx_ccmp_and(a, b, c, d);
    apx_sink += apx_ccmp_or(a, b, c, d);
    apx_sink += apx_ccmp_range(a, b, c);

    /* NDD CMOV tests */
    apx_sink += apx_ndd_ternary(a, b, c);
    apx_sink += apx_ndd_min(a, b);
    apx_sink += apx_ndd_clamp(a, b, c);

    /* CFCMOV tests */
    apx_sink += apx_cfcmov_load(a, &buf[0]);
    apx_cfcmov_store(a, &buf[1], b);
    apx_sink += buf[1];

    /* Inlineable versions */
    apx_sink += apx_ccmp_and_inline(a, b, c, d);
    apx_sink += apx_ndd_ternary_inline(a, b, c);
    apx_sink += apx_ccmp_range_inline(a, b, c);
}

#endif /* APX_INSERT_H */
