#!/bin/bash
# APX Differential Fuzzer
#
# Tests whether APX optimization decisions preserve program semantics.
# Strategy: compile CSmith programs to LLVM IR with APX flags, strip APX
# target features, recompile to native x86_64, and compare checksums.
#
# This runs INSIDE the Docker container.

set -uo pipefail

NUM=${1:-100}
START_SEED=${2:-10000}
CSMITH_PATH="${CSMITH_PATH:-/usr/include/csmith}"

CSMITH_OPTS="--max-funcs 3 --max-block-depth 2 --max-expr-complexity 3 --no-volatiles"
TIMEOUT=10

match=0
mismatch=0
crash=0
timeout_count=0
compile_fail=0
total=0

echo "========================================================================"
echo "APX DIFFERENTIAL FUZZER"
echo "Programs: $NUM | Seeds: $START_SEED-$((START_SEED + NUM - 1))"
echo "CSmith opts: $CSMITH_OPTS"
echo "========================================================================"
echo ""

strip_apx_features() {
    sed -i 's/+ccmp,//g; s/+ndd,//g; s/+egpr,//g; s/+push2pop2,//g; s/+ppx,//g; s/+nf,//g; s/+zu,//g; s/+cf,//g; s/,+ccmp//g; s/,+ndd//g; s/,+egpr//g; s/,+push2pop2//g; s/,+ppx//g; s/,+nf//g; s/,+zu//g; s/,+cf//g' "$1"
}

for seed in $(seq $START_SEED $((START_SEED + NUM - 1))); do
    ((total++))

    # Generate CSmith program
    csmith --seed "$seed" $CSMITH_OPTS > /tmp/fuzz.c 2>/dev/null

    # Path 1: Baseline (no APX)
    if ! clang -O2 -w -I"$CSMITH_PATH" -o /tmp/fuzz_base /tmp/fuzz.c -lm 2>/dev/null; then
        ((compile_fail++))
        continue
    fi

    # Path 2: APX optimization → IR → strip → native
    if ! clang -O2 -w -mapxf -emit-llvm -S -I"$CSMITH_PATH" -o /tmp/fuzz_apx.ll /tmp/fuzz.c 2>/dev/null; then
        ((compile_fail++))
        continue
    fi
    strip_apx_features /tmp/fuzz_apx.ll
    if ! clang -O2 -w -o /tmp/fuzz_apx /tmp/fuzz_apx.ll -lm 2>/dev/null; then
        ((compile_fail++))
        continue
    fi

    # Path 3: APX+CF optimization → IR → strip → native
    if ! clang -O2 -w -mapxf -Xclang -target-feature -Xclang +cf -emit-llvm -S -I"$CSMITH_PATH" -o /tmp/fuzz_cf.ll /tmp/fuzz.c 2>/dev/null; then
        ((compile_fail++))
        continue
    fi
    strip_apx_features /tmp/fuzz_cf.ll
    if ! clang -O2 -w -o /tmp/fuzz_cf /tmp/fuzz_cf.ll -lm 2>/dev/null; then
        ((compile_fail++))
        continue
    fi

    # Run all three
    out_base=$(timeout $TIMEOUT /tmp/fuzz_base 2>&1)
    exit_base=$?
    out_apx=$(timeout $TIMEOUT /tmp/fuzz_apx 2>&1)
    exit_apx=$?
    out_cf=$(timeout $TIMEOUT /tmp/fuzz_cf 2>&1)
    exit_cf=$?

    # Handle timeouts
    if [ $exit_base -eq 124 ] || [ $exit_apx -eq 124 ] || [ $exit_cf -eq 124 ]; then
        ((timeout_count++))
        continue
    fi

    # Handle crashes
    if [ $exit_base -ne 0 ] || [ $exit_apx -ne 0 ] || [ $exit_cf -ne 0 ]; then
        ((crash++))
        if [ $exit_base -eq 0 ] && [ $exit_apx -ne 0 ]; then
            echo "CRASH: seed=$seed — APX crashed (exit=$exit_apx) but baseline OK"
        fi
        if [ $exit_base -eq 0 ] && [ $exit_cf -ne 0 ]; then
            echo "CRASH: seed=$seed — APX+CF crashed (exit=$exit_cf) but baseline OK"
        fi
        continue
    fi

    # Compare checksums
    if [ "$out_base" = "$out_apx" ] && [ "$out_base" = "$out_cf" ]; then
        ((match++))
    else
        ((mismatch++))
        echo "MISMATCH: seed=$seed"
        echo "  Base:   $out_base"
        echo "  APX:    $out_apx"
        echo "  APX+CF: $out_cf"
        # Save the offending source
        cp /tmp/fuzz.c "/tmp/mismatch_${seed}.c"
    fi

    # Progress
    if (( total % 25 == 0 )); then
        echo "  [$total/$NUM] match=$match mismatch=$mismatch crash=$crash timeout=$timeout_count compile_fail=$compile_fail"
    fi
done

echo ""
echo "========================================================================"
echo "RESULTS ($total programs)"
echo "========================================================================"
echo "  Match:        $match"
echo "  Mismatch:     $mismatch"
echo "  Crash:        $crash"
echo "  Timeout:      $timeout_count"
echo "  Compile fail: $compile_fail"
echo ""

if [ $mismatch -gt 0 ]; then
    echo "MISMATCHES FOUND — potential APX miscompilation bugs!"
    echo "Saved to /tmp/mismatch_*.c"
else
    echo "No mismatches found — APX optimizations appear semantically correct."
fi
