#!/bin/zsh
# CSmith APX Insertion Pipeline
#
# Generates random C programs, inserts APX archetypal functions,
# compiles with/without APX flags, and checks whether APX instructions
# survive in the combined program vs isolation.
#
# Usage: ./scripts/csmith_pipeline.sh [num_programs] [start_seed]

set -uo pipefail

NUM_PROGRAMS=${1:-50}
START_SEED=${2:-1000}

CLANG="/opt/homebrew/opt/llvm/bin/clang"
TARGET="x86_64-apple-macos"
SYSROOT=$(xcrun --sdk macosx --show-sdk-path)
CSMITH_PATH="/opt/homebrew/Cellar/csmith/2.3.0/include/csmith-2.3.0"
INSERT_HEADER="CSmith/apx_insert.h"
OUTDIR="CSmith/results"

mkdir -p "$OUTDIR"

# ─────────────────────────────────────────────────────────────────────────
# Step 1: Establish baseline — compile archetypes in isolation
# ─────────────────────────────────────────────────────────────────────────
echo "=== Step 1: Baseline (archetypes in isolation) ==="

# Create a minimal driver that includes the archetypes
cat > /tmp/apx_baseline.c << 'BASELINE'
#include <stdint.h>
#include "apx_insert.h"

int main(void) {
    volatile int a = 1, b = 2, c = 3, d = 4;
    apx_harness(a, b, c, d);
    return apx_sink;
}
BASELINE

# Compile baseline with APX
$CLANG -S --target="$TARGET" -isysroot "$SYSROOT" -O2 -mapxf \
    -I"$CSMITH_PATH" -ICSmith -w \
    -o "$OUTDIR/baseline_apx.s" /tmp/apx_baseline.c 2>/dev/null

# Compile baseline with APX + CF
$CLANG -S --target="$TARGET" -isysroot "$SYSROOT" -O2 -mapxf \
    -Xclang -target-feature -Xclang +cf \
    -I"$CSMITH_PATH" -ICSmith -w \
    -o "$OUTDIR/baseline_apx_cf.s" /tmp/apx_baseline.c 2>/dev/null

# Count baseline APX instructions per function
count_apx_in_func() {
    local file="$1"
    local func="$2"
    awk -v f="${func}:" '
        $0 ~ f { found=1 }
        found && /\t(ccmp|ctest|cfcmov|push2|pop2)/ { count++ }
        found && /\tcmov[a-z]+\t%[a-z0-9]+, %[a-z0-9]+, %[a-z0-9]+/ { count++ }
        found && /\tretq/ { exit }
        END { print count+0 }
    ' "$file"
}

echo ""
echo "Baseline APX instruction counts (noinline functions):"
for func in _apx_ccmp_and _apx_ccmp_or _apx_ccmp_range _apx_ndd_ternary _apx_ndd_min _apx_ndd_clamp; do
    c=$(count_apx_in_func "$OUTDIR/baseline_apx.s" "$func")
    echo "  $func: $c"
done

echo ""
echo "Baseline CFCMOV counts (with +cf):"
for func in _apx_cfcmov_load _apx_cfcmov_store; do
    c=$(count_apx_in_func "$OUTDIR/baseline_apx_cf.s" "$func")
    echo "  $func: $c"
done

# ─────────────────────────────────────────────────────────────────────────
# Step 2: Generate CSmith programs and insert archetypes
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Step 2: Generating $NUM_PROGRAMS CSmith programs (seeds $START_SEED–$((START_SEED + NUM_PROGRAMS - 1))) ==="

# Track results
noinline_pass=0
noinline_fail=0
inline_pass=0
inline_fail=0
cfcmov_pass=0
cfcmov_fail=0
compile_fail=0
total=0

# CSV output
echo "seed,compiled,noinline_ccmp,noinline_ndd,noinline_total,inline_ccmp,inline_ndd,inline_total,cfcmov_count" > "$OUTDIR/results.csv"

for seed in $(seq $START_SEED $((START_SEED + NUM_PROGRAMS - 1))); do
    ((total++))

    # Generate CSmith program
    csmith_file="$OUTDIR/csmith_${seed}.c"
    csmith --seed "$seed" --no-checksum --no-argc > "$csmith_file" 2>/dev/null

    # Insert our header and harness call
    # Use volatile globals to prevent constant folding — no dependency on CSmith names
    combined_file="$OUTDIR/combined_${seed}.c"
    {
        echo '#include "apx_insert.h"'
        cat "$csmith_file"
        echo ''
        echo 'static volatile int apx_a = 42, apx_b = 17, apx_c = 100, apx_d = 3;'
        echo 'void apx_test_hook(void) {'
        echo '    apx_harness(apx_a, apx_b, apx_c, apx_d);'
        echo '}'
    } > "$combined_file" 2>/dev/null

    # Compile combined program with APX
    apx_asm="$OUTDIR/combined_${seed}_apx.s"
    if ! $CLANG -S --target="$TARGET" -isysroot "$SYSROOT" -O2 -mapxf \
        -I"$CSMITH_PATH" -ICSmith -w \
        -o "$apx_asm" "$combined_file" 2>/dev/null; then
        ((compile_fail++))
        echo "$seed,0,0,0,0,0,0,0,0" >> "$OUTDIR/results.csv"
        continue
    fi

    # Also compile with +cf
    apx_cf_asm="$OUTDIR/combined_${seed}_apx_cf.s"
    $CLANG -S --target="$TARGET" -isysroot "$SYSROOT" -O2 -mapxf \
        -Xclang -target-feature -Xclang +cf \
        -I"$CSMITH_PATH" -ICSmith -w \
        -o "$apx_cf_asm" "$combined_file" 2>/dev/null

    # Count APX instructions in noinline functions
    noinline_ccmp=0
    noinline_ndd=0
    for func in _apx_ccmp_and _apx_ccmp_or _apx_ccmp_range; do
        c=$(count_apx_in_func "$apx_asm" "$func")
        ((noinline_ccmp += c))
    done
    for func in _apx_ndd_ternary _apx_ndd_min _apx_ndd_clamp; do
        c=$(count_apx_in_func "$apx_asm" "$func")
        ((noinline_ndd += c))
    done
    noinline_total=$((noinline_ccmp + noinline_ndd))

    if [ "$noinline_total" -gt 0 ]; then
        ((noinline_pass++))
    else
        ((noinline_fail++))
    fi

    # Count APX instructions in inlineable functions (in the harness or caller)
    # These may have been inlined into apx_test_hook or apx_harness
    inline_ccmp=$(grep -cE '^\s+ccmp' "$apx_asm" 2>/dev/null) || inline_ccmp=0
    inline_ndd=$(grep -cE '^\s+cmov\w+\s+%\w+,\s*%\w+,\s*%\w+' "$apx_asm" 2>/dev/null) || inline_ndd=0
    # Subtract noinline counts to get inline-only
    inline_ccmp=$((inline_ccmp - noinline_ccmp))
    inline_ndd=$((inline_ndd - noinline_ndd))
    inline_total=$((inline_ccmp + inline_ndd))

    if [ "$inline_total" -gt 0 ]; then
        ((inline_pass++))
    else
        ((inline_fail++))
    fi

    # Count CFCMOV in +cf version
    cfcmov_count=0
    if [ -f "$apx_cf_asm" ]; then
        cfcmov_count=$(grep -cE '^\s+cfcmov' "$apx_cf_asm" 2>/dev/null) || cfcmov_count=0
    fi
    if [ "$cfcmov_count" -gt 0 ]; then
        ((cfcmov_pass++))
    else
        ((cfcmov_fail++))
    fi

    echo "$seed,1,$noinline_ccmp,$noinline_ndd,$noinline_total,$inline_ccmp,$inline_ndd,$inline_total,$cfcmov_count" >> "$OUTDIR/results.csv"

    # Progress
    if (( total % 10 == 0 )); then
        echo "  Processed $total/$NUM_PROGRAMS..."
    fi
done

# ─────────────────────────────────────────────────────────────────────────
# Step 3: Report
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "================================================================================"
echo "CSMITH APX INSERTION RESULTS ($NUM_PROGRAMS programs)"
echo "================================================================================"
echo ""
echo "Compilation: $((total - compile_fail)) succeeded, $compile_fail failed"
echo ""
echo "── Noinline functions (should always retain APX instructions) ──"
echo "  Pass (APX instructions present): $noinline_pass"
echo "  Fail (APX instructions missing): $noinline_fail"
if [ "$((noinline_pass + noinline_fail))" -gt 0 ]; then
    echo "  Rate: $(( noinline_pass * 100 / (noinline_pass + noinline_fail) ))%"
fi
echo ""
echo "── Inlineable functions (may lose APX instructions due to optimization) ──"
echo "  Pass (APX instructions present): $inline_pass"
echo "  Fail (APX instructions missing): $inline_fail"
if [ "$((inline_pass + inline_fail))" -gt 0 ]; then
    echo "  Rate: $(( inline_pass * 100 / (inline_pass + inline_fail) ))%"
fi
echo ""
echo "── CFCMOV (with +cf) ──"
echo "  Pass (CFCMOV present): $cfcmov_pass"
echo "  Fail (CFCMOV missing): $cfcmov_fail"
if [ "$((cfcmov_pass + cfcmov_fail))" -gt 0 ]; then
    echo "  Rate: $(( cfcmov_pass * 100 / (cfcmov_pass + cfcmov_fail) ))%"
fi
echo ""
echo "Results CSV: $OUTDIR/results.csv"

# Clean up intermediate files (keep CSV and baseline)
echo ""
echo "Cleaning up intermediate .c and .s files..."
rm -f "$OUTDIR"/csmith_*.c "$OUTDIR"/combined_*.c "$OUTDIR"/combined_*.s
