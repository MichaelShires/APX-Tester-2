/**
 * CCMP Archetype — Conditional Compare
 *
 * CCMP allows chaining comparisons without branching between them.
 * Instead of: CMP a, b → JNE skip → CMP c, d → ...
 * APX can:    CMP a, b → CCMP c, d, <defcc>, <cond>
 *
 * The canonical pattern is a compound conditional where both conditions
 * must be true (logical AND) or either can be true (logical OR).
 */

/* Archetype 1: Simple compound AND — the most direct CCMP pattern.
 * Without CCMP: two compares with a branch between them.
 * With CCMP: first CMP sets flags, CCMP chains the second compare. */
int ccmp_compound_and(int a, int b, int x, int y) {
    if (a > x && b < y) {
        return 1;
    }
    return 0;
}

/* Archetype 2: Compound OR — CCMP can also handle disjunctions
 * by inverting the condition code. */
int ccmp_compound_or(int a, int b, int x, int y) {
    if (a > x || b < y) {
        return 1;
    }
    return 0;
}

/* Archetype 3: Triple compound — tests deeper chaining.
 * Should produce CMP → CCMP → CCMP. */
int ccmp_triple(int a, int b, int c, int lo, int mid, int hi) {
    if (a > lo && b > mid && c > hi) {
        return 1;
    }
    return 0;
}

/* Archetype 4: Range check — a very common real-world pattern.
 * Checking if a value is within bounds. */
int ccmp_range_check(int val, int lo, int hi) {
    if (val >= lo && val <= hi) {
        return 1;
    }
    return 0;
}

/* Archetype 5: Mixed types — compound conditional with different
 * comparison operations. */
int ccmp_mixed(long a, long b, int threshold) {
    if (a != 0 && b > (long)threshold) {
        return (int)(a + b);
    }
    return 0;
}
