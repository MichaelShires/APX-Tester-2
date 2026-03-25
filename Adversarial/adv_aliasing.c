/**
 * Adversarial: Pointer Aliasing
 *
 * Aliasing prevents the compiler from reasoning about memory,
 * which may block SimplifyCFG from hoisting conditional loads (CFCMOV)
 * or combining comparisons (CCMP).
 */

/* CCMP target: compound conditional through aliased pointers.
 * The compiler can't prove *a and *b don't alias, which may
 * prevent it from combining the comparisons. */
int adv_ccmp_aliased(int *a, int *b, int x, int y) {
    if (*a > x && *b < y)
        return 1;
    return 0;
}

/* Same but with restrict — should recover the CCMP pattern. */
int adv_ccmp_restrict(int *restrict a, int *restrict b, int x, int y) {
    if (*a > x && *b < y)
        return 1;
    return 0;
}

/* CFCMOV target: conditional load through potentially-aliased pointer.
 * The store to *out before the conditional load of *ptr may prevent
 * CFCMOV if the compiler thinks they could alias. */
int adv_cfcmov_alias_store(int cond, int *ptr, int *out) {
    *out = 42;
    if (cond)
        return *ptr;
    return 0;
}

/* Same with restrict — should recover CFCMOV. */
int adv_cfcmov_restrict(int cond, int *restrict ptr, int *restrict out) {
    *out = 42;
    if (cond)
        return *ptr;
    return 0;
}

/* NDD CMOV target: conditional assignment through aliased memory. */
int adv_ndd_aliased(int *a, int *b, int cond) {
    return cond > 0 ? *a : *b;
}

/* Deep aliasing: compound conditional where each comparison
 * accesses memory that might alias with the other. */
int adv_ccmp_deep_alias(int *p1, int *p2, int *p3, int *p4) {
    if (*p1 > *p2 && *p3 < *p4)
        return 1;
    return 0;
}
