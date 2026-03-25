/**
 * Adversarial: Inlining and Interprocedural Optimization
 *
 * Test whether inlining our archetypal functions into complex
 * callers destroys the APX pattern. Focus on cases where
 * inlining merges the function's control flow with the caller's.
 */

/* Helper that should be inlined — contains CCMP pattern. */
static inline int ccmp_helper(int a, int b, int x, int y) {
    if (a > x && b < y)
        return 1;
    return 0;
}

/* Helper that should be inlined — contains NDD CMOV pattern. */
static inline int ndd_helper(int a, int b, int cond) {
    return cond > 0 ? a : b;
}

/* Caller that uses the CCMP result in a complex way.
 * After inlining, the compound conditional is embedded in
 * a larger control flow graph with phi nodes. */
int adv_inline_ccmp_complex(int *arr, int n, int x, int y) {
    int sum = 0;
    for (int i = 0; i < n; i++) {
        int val = arr[i];
        /* After inlining, this becomes a compound conditional
         * inside a loop with a dependent accumulation. */
        if (ccmp_helper(val, arr[(i+1) % n], x, y)) {
            sum += val;
        } else {
            sum -= val;
        }
    }
    return sum;
}

/* Multiple inlined calls with overlapping live ranges. */
int adv_inline_multiple(int a, int b, int c, int d) {
    int r1 = ccmp_helper(a, b, c, d);
    int r2 = ccmp_helper(b, c, d, a);
    int r3 = ndd_helper(a, b, r1);
    int r4 = ndd_helper(c, d, r2);
    return r1 + r2 + r3 + r4;
}

/* Chain of inlined ternaries — tests if NDD CMOV survives
 * when multiple conditional moves are chained. */
int adv_inline_chain(int a, int b, int c, int d) {
    int x = ndd_helper(a, b, a - b);
    int y = ndd_helper(x, c, x - c);
    int z = ndd_helper(y, d, y - d);
    return z;
}

/* PUSH2/POP2 test: calling a large function from inside a loop.
 * If the loop body is inlined, the function boundary disappears
 * and PUSH2/POP2 opportunities may vanish. */
extern long external_work(long a, long b, long c);

static inline long big_helper(long a, long b, long c, long d) {
    long r1 = a * 3 + b;
    long r2 = c * 5 + d;
    long r3 = a * 7 + c;
    long mid = external_work(r1, r2, r3);
    return mid + r1 + r2 + r3;
}

long adv_inline_push2(long *data, int n) {
    long sum = 0;
    for (int i = 0; i < n - 3; i += 4) {
        sum += big_helper(data[i], data[i+1], data[i+2], data[i+3]);
    }
    return sum;
}
