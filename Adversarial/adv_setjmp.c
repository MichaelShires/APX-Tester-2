/**
 * Adversarial: setjmp/longjmp
 *
 * setjmp forces the compiler to assume all local variables may be
 * modified between setjmp and longjmp, pushing them to memory.
 * This may prevent register-based patterns like CCMP and NDD CMOV.
 */

#include <setjmp.h>

static jmp_buf env;

/* CCMP target: compound conditional with setjmp in scope.
 * All locals must be volatile or memory-resident after setjmp. */
int adv_ccmp_setjmp(int a, int b, int x, int y) {
    volatile int va = a, vb = b;
    if (setjmp(env) != 0)
        return -1;
    if (va > x && vb < y)
        return 1;
    return 0;
}

/* Same pattern without setjmp — control case. */
int adv_ccmp_no_setjmp(int a, int b, int x, int y) {
    volatile int va = a, vb = b;
    if (va > x && vb < y)
        return 1;
    return 0;
}

/* NDD CMOV target with setjmp. */
int adv_ndd_setjmp(int a, int b, int cond) {
    volatile int va = a, vb = b;
    if (setjmp(env) != 0)
        return -1;
    return cond > 0 ? va : vb;
}

/* PUSH2/POP2 target: function with many callee-saved regs + setjmp.
 * setjmp may force different register allocation strategies. */
extern long external_call(long x);

long adv_push2_setjmp(long a, long b, long c, long d) {
    long r1 = a + b;
    long r2 = c + d;
    long r3 = a * c;
    long r4 = b * d;

    if (setjmp(env) != 0)
        return -1;

    long mid = external_call(r1 + r2);
    return mid + r3 + r4 + r1 - r2;
}
