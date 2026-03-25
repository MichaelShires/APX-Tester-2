/**
 * PUSH2/POP2 Archetype — Paired Push/Pop
 *
 * PUSH2/POP2 save and restore two registers in a single instruction,
 * reducing prologue/epilogue code size and improving throughput.
 *
 * The pattern: functions that use many callee-saved registers
 * (rbx, r12-r15 on System V AMD64 ABI), forcing the compiler to
 * spill multiple registers in the prologue.
 *
 * The threat: aggressive inlining eliminates function boundaries,
 * removing the prologue/epilogue where PUSH2/POP2 would appear.
 */

/* Archetype 1: Heavy register pressure — uses enough callee-saved
 * registers that the prologue must save at least 4 (ideal for 2x PUSH2). */
long push2pop2_register_pressure(long a, long b, long c, long d,
                                  long e, long f) {
    /* Force use of callee-saved registers by creating values that
     * must survive across a call-clobbering boundary. We use volatile
     * to prevent the optimizer from simplifying this away. */
    long r1 = a * 3 + b;
    long r2 = c * 5 + d;
    long r3 = e * 7 + f;
    long r4 = a * 11 + c;
    long r5 = b * 13 + e;
    long r6 = d * 17 + f;

    /* Mix all values to prevent dead code elimination */
    long result = r1 ^ r2;
    result += r3 ^ r4;
    result += r5 ^ r6;
    result ^= (r1 + r3 + r5);
    result ^= (r2 + r4 + r6);

    return result;
}

/* External function declaration to create a call boundary that forces
 * register spilling. */
extern long external_call(long x);

/* Archetype 2: Register pressure across a call — the external call
 * forces callee-saved registers to actually be saved/restored. */
long push2pop2_across_call(long a, long b, long c, long d) {
    long r1 = a + b;
    long r2 = c + d;
    long r3 = a * c;
    long r4 = b * d;

    /* Call forces r1-r4 into callee-saved registers */
    long mid = external_call(r1 + r2);

    return mid + r3 + r4 + r1 - r2;
}

/* Archetype 3: Multiple calls — even more register pressure. */
long push2pop2_multi_call(long a, long b, long c, long d, long e) {
    long r1 = a + b;
    long r2 = c + d;
    long r3 = a * e;
    long r4 = b * c;
    long r5 = d * e;

    long x = external_call(r1);
    long y = external_call(r2 + x);

    return y + r3 + r4 + r5 + r1 - r2;
}

/* Archetype 4: Recursive function — each recursive call requires
 * full save/restore of live registers. */
long push2pop2_recursive(long n, long a, long b, long c, long d) {
    if (n <= 0) return a + b + c + d;

    long x = a * 3 + b;
    long y = c * 5 + d;

    long sub = push2pop2_recursive(n - 1, x, y, a + c, b + d);

    return sub + x + y;
}
