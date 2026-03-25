/**
 * Adversarial: Complex Control Flow
 *
 * Computed gotos, switch statements, and indirect calls create
 * complex CFGs that may prevent SimplifyCFG from recognizing
 * compound conditional patterns.
 */

/* CCMP target: compound conditional inside computed goto dispatch. */
int adv_ccmp_computed_goto(int a, int b, int x, int y, int which) {
    static void *targets[] = { &&L0, &&L1, &&L2 };
    goto *targets[which % 3];

L0:
    if (a > x && b < y)
        return 1;
    return 0;

L1:
    if (a < x && b > y)
        return 2;
    return 0;

L2:
    if (a == x && b == y)
        return 3;
    return 0;
}

/* CCMP target: compound conditional buried inside deep switch. */
int adv_ccmp_switch(int sel, int a, int b, int x, int y) {
    switch (sel) {
    case 0: return a + b;
    case 1: return a - b;
    case 2:
        if (a > x && b < y)
            return 100;
        return 0;
    case 3: return a * b;
    case 4:
        if (a >= x || b <= y)
            return 200;
        return 0;
    default: return -1;
    }
}

/* CCMP target: compound conditional where one side has side effects. */
extern int side_effect(int x);

int adv_ccmp_side_effect(int a, int b, int x, int y) {
    if (side_effect(a) > x && b < y)
        return 1;
    return 0;
}

/* Triple compound with interleaved function calls.
 * Can CCMP chain through call boundaries? */
int adv_ccmp_interleaved_calls(int a, int b, int c, int lo, int mid, int hi) {
    int r1 = side_effect(a);
    int r2 = side_effect(b);
    if (r1 > lo && r2 > mid && c > hi)
        return 1;
    return 0;
}

/* NDD CMOV inside a hot loop with indirect call. */
typedef int (*transform_fn)(int);

int adv_ndd_indirect(int *data, int n, int threshold, transform_fn fn) {
    int result = 0;
    for (int i = 0; i < n; i++) {
        int val = fn(data[i]);
        result += val > threshold ? val : 0;
    }
    return result;
}
