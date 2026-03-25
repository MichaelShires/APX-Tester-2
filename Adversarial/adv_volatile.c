/**
 * Adversarial: Volatile Access
 *
 * Volatile forces memory access on every read/write, preventing
 * the compiler from keeping values in registers. This may block
 * CCMP (needs register compares) and NDD CMOV.
 */

/* CCMP target: compound conditional with volatile operands.
 * Each access must go to memory — can LLVM still chain compares? */
int adv_ccmp_volatile(volatile int *a, volatile int *b, int x, int y) {
    if (*a > x && *b < y)
        return 1;
    return 0;
}

/* CCMP with volatile locals. */
int adv_ccmp_volatile_local(int a, int b, int x, int y) {
    volatile int va = a, vb = b;
    if (va > x && vb < y)
        return 1;
    return 0;
}

/* NDD CMOV with volatile. */
int adv_ndd_volatile(volatile int *a, volatile int *b, int cond) {
    return cond > 0 ? *a : *b;
}

/* Range check with volatile — still recognizable? */
int adv_ccmp_range_volatile(volatile int *val, int lo, int hi) {
    if (*val >= lo && *val <= hi)
        return 1;
    return 0;
}

/* CFCMOV: conditional load from volatile — can it be hoisted? */
int adv_cfcmov_volatile(int cond, volatile int *ptr) {
    if (cond)
        return *ptr;
    return 0;
}
