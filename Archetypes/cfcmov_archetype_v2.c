/**
 * CFCMOV Archetype v2 — Conditional Faulting Conditional Move
 *
 * CFCMOV is NOT a general-purpose conditional move. Its key property is
 * **conditional faulting**: when the condition is false and the operand
 * is a memory address, all memory faults are suppressed. This makes it
 * safe to speculatively execute a conditional load/store.
 *
 * LLVM emits CFCMOV via SimplifyCFG's "conditional faulting" optimization,
 * which hoists guarded memory accesses into masked load/store intrinsics.
 *
 * Patterns that trigger CFCMOV:
 *   - Conditional loads:  if (cond) x = *ptr;
 *   - Conditional stores: if (cond) *ptr = x;
 *   - Zeroing cmov:       x = cond ? val : 0;  (register-to-register)
 */

/* Archetype 1: Conditional load — branch guards a memory read.
 * SimplifyCFG should hoist this into a CFCMOV rm (conditional load). */
int cfcmov_cond_load(int cond, const int *ptr) {
    if (cond)
        return *ptr;
    return 0;
}

/* Archetype 2: Conditional store — branch guards a memory write.
 * Should produce CFCMOV mr (conditional store). */
void cfcmov_cond_store(int cond, int *ptr, int val) {
    if (cond)
        *ptr = val;
}

/* Archetype 3: Conditional load with default — common null-check pattern. */
int cfcmov_null_check_load(const int *ptr) {
    if (ptr)
        return *ptr;
    return -1;
}

/* Archetype 4: Zeroing conditional move — one operand is literal zero.
 * Should match CFCMOVrr (zeroing form). */
int cfcmov_zeroing(int a, int b) {
    return a > b ? a : 0;
}

/* Archetype 5: Conditional load in a loop — filter pattern.
 * Load from array only if index is valid. */
long cfcmov_filtered_sum(const int *data, const int *indices, int n, int limit) {
    long sum = 0;
    for (int i = 0; i < n; i++) {
        int idx = indices[i];
        if (idx >= 0 && idx < limit)
            sum += data[idx];
    }
    return sum;
}

/* Archetype 6: Conditional store in a loop — sparse update pattern. */
void cfcmov_sparse_update(int *dst, const int *src, const int *mask, int n) {
    for (int i = 0; i < n; i++) {
        if (mask[i])
            dst[i] = src[i];
    }
}

/* Archetype 7: Conditional load from two pointers — one may be invalid. */
int cfcmov_safe_deref(int use_a, const int *a, const int *b) {
    if (use_a)
        return *a;
    return *b;
}
