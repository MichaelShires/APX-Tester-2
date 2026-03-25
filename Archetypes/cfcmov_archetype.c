/**
 * CFCMOV Archetype — Conditional Fused Move
 *
 * CFCMOV is an enhanced conditional move that can operate on memory
 * operands and preserves flags. The source-level pattern is conditional
 * assignment: x = cond ? a : b
 *
 * Unlike regular CMOV which only works register-to-register, CFCMOV
 * can load from memory conditionally, avoiding a potentially expensive
 * unconditional load.
 */

/* Archetype 1: Simple ternary — the most direct CFCMOV pattern. */
int cfcmov_simple_ternary(int a, int b, int cond) {
    return cond > 0 ? a : b;
}

/* Archetype 2: Min/max — extremely common pattern that should
 * map to a compare + conditional move. */
int cfcmov_min(int a, int b) {
    return a < b ? a : b;
}

int cfcmov_max(int a, int b) {
    return a > b ? a : b;
}

/* Archetype 3: Absolute value — classic branchless pattern. */
int cfcmov_abs(int x) {
    return x < 0 ? -x : x;
}

/* Archetype 4: Clamp — combines min and max, two conditional moves. */
int cfcmov_clamp(int val, int lo, int hi) {
    int result = val;
    if (result < lo) result = lo;
    if (result > hi) result = hi;
    return result;
}

/* Archetype 5: Conditional select from pointers — tests CFCMOV's
 * ability to do conditional memory loads. */
int cfcmov_select_ptr(const int *a, const int *b, int use_first) {
    return use_first ? *a : *b;
}

/* Archetype 6: Branchless conditional accumulation. */
long cfcmov_accumulate(const int *data, int n, int threshold) {
    long sum = 0;
    for (int i = 0; i < n; i++) {
        int val = data[i];
        sum += val > threshold ? val : 0;
    }
    return sum;
}
