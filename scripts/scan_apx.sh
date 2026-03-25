#!/bin/zsh
# Scan SPEC assembly output for APX instruction usage.
# Compares APX-compiled assembly against non-APX baseline.

set -uo pipefail

ASMBASE="SPEC/asm"

echo "================================================================================"
echo "APX INSTRUCTION USAGE IN SPEC CPU 2017 BENCHMARKS"
echo "Compiler: Homebrew clang 22.1.1 | Optimization: -O2 | Flags: -mapxf"
echo "================================================================================"
echo ""

total_ccmp=0
total_ctest=0
total_ndd_cmov=0
total_push2=0
total_pop2=0
total_files=0

for bench in 505.mcf_r 557.xz_r 525.x264_r 538.imagick_r 502.gcc_r; do
    apx_dir="$ASMBASE/$bench/apx"
    [ -d "$apx_dir" ] || continue

    bench_ccmp=0
    bench_ctest=0
    bench_ndd_cmov=0
    bench_push2=0
    bench_pop2=0
    bench_files=0

    for asmfile in "$apx_dir"/*.s; do
        [ -f "$asmfile" ] || continue
        ((bench_files++))

        # Count CCMP/CTEST (instruction opcodes only, not labels/function names)
        c=$(grep -cE '^\s+ccmp' "$asmfile" 2>/dev/null) || c=0
        ((bench_ccmp += c))

        c=$(grep -cE '^\s+ctest' "$asmfile" 2>/dev/null) || c=0
        ((bench_ctest += c))

        # Count NDD CMOV (3-operand cmov: cmovXX %reg, %reg, %reg)
        c=$(grep -cE '^\s+cmov\w+\s+%\w+,\s*%\w+,\s*%\w+' "$asmfile" 2>/dev/null) || c=0
        ((bench_ndd_cmov += c))

        # Count PUSH2/POP2
        c=$(grep -cE '^\s+push2' "$asmfile" 2>/dev/null) || c=0
        ((bench_push2 += c))

        c=$(grep -cE '^\s+pop2' "$asmfile" 2>/dev/null) || c=0
        ((bench_pop2 += c))
    done

    echo "--- $bench ($bench_files files) ---"
    echo "  CCMP:      $bench_ccmp"
    echo "  CTEST:     $bench_ctest"
    echo "  NDD CMOV:  $bench_ndd_cmov"
    echo "  PUSH2:     $bench_push2"
    echo "  POP2:      $bench_pop2"
    echo ""

    ((total_ccmp += bench_ccmp))
    ((total_ctest += bench_ctest))
    ((total_ndd_cmov += bench_ndd_cmov))
    ((total_push2 += bench_push2))
    ((total_pop2 += bench_pop2))
    ((total_files += bench_files))
done

echo "================================================================================"
echo "TOTALS ($total_files files across 5 benchmarks)"
echo "================================================================================"
echo "  CCMP:      $total_ccmp"
echo "  CTEST:     $total_ctest"
echo "  NDD CMOV:  $total_ndd_cmov"
echo "  PUSH2:     $total_push2"
echo "  POP2:      $total_pop2"
echo ""

# Top files by APX instruction count
echo "================================================================================"
echo "TOP 15 FILES BY TOTAL APX INSTRUCTION COUNT"
echo "================================================================================"
for bench in 505.mcf_r 557.xz_r 525.x264_r 538.imagick_r 502.gcc_r; do
    apx_dir="$ASMBASE/$bench/apx"
    [ -d "$apx_dir" ] || continue

    for asmfile in "$apx_dir"/*.s; do
        [ -f "$asmfile" ] || continue
        total=$(grep -cE '^\s+(ccmp|ctest|push2|pop2|cmov\w+\s+%\w+,\s*%\w+,\s*%\w+)' "$asmfile" 2>/dev/null) || total=0
        if [ "$total" -gt 0 ]; then
            echo "$total $bench/$(basename "$asmfile")"
        fi
    done
done | sort -rn | head -15
