#!/bin/zsh
# Find missed APX instruction opportunities by analyzing non-APX assembly
# and comparing against APX assembly output.

set -uo pipefail

ASMBASE="SPEC/asm"

echo "================================================================================"
echo "MISSED APX OPPORTUNITY ANALYSIS"
echo "================================================================================"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 1. CCMP missed opportunities
#    Pattern in non-APX: two CMP/TEST instructions close together followed by
#    SETcc + AND/OR (compound conditional lowered to branchless setcc chain)
#    or two CMP+Jcc in sequence (compound conditional lowered to branches)
# ─────────────────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════════════════════"
echo "1. POTENTIAL CCMP PATTERNS (consecutive CMP+SETcc+AND/OR in non-APX)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

total_noapx_setcc_chains=0
total_apx_ccmp=0

for bench in 505.mcf_r 557.xz_r 525.x264_r 538.imagick_r 502.gcc_r; do
    noapx_dir="$ASMBASE/$bench/noapx"
    apx_dir="$ASMBASE/$bench/apx"
    [ -d "$noapx_dir" ] || continue

    bench_noapx_patterns=0
    bench_apx_ccmp=0

    for noapx_file in "$noapx_dir"/*.s; do
        [ -f "$noapx_file" ] || continue
        basename=$(basename "$noapx_file")
        apx_file="$apx_dir/$basename"

        # Count SETcc+AND/OR chains in non-APX (proxy for compound conditionals)
        # Pattern: setXX followed within 3 lines by andb/orb
        noapx_count=$(grep -cE '^\s+(andb|orb)\s+%[a-z]+,\s*%[a-z]+' "$noapx_file" 2>/dev/null) || noapx_count=0
        ((bench_noapx_patterns += noapx_count))

        # Count CCMP in APX version
        if [ -f "$apx_file" ]; then
            apx_count=$(grep -cE '^\s+ccmp' "$apx_file" 2>/dev/null) || apx_count=0
            ((bench_apx_ccmp += apx_count))
        fi
    done

    conversion_rate=0
    if [ "$bench_noapx_patterns" -gt 0 ]; then
        conversion_rate=$(( (bench_apx_ccmp * 100) / bench_noapx_patterns ))
    fi

    echo "$bench:"
    echo "  Non-APX compound conditional patterns (andb/orb on setcc): $bench_noapx_patterns"
    echo "  APX CCMP instructions: $bench_apx_ccmp"
    echo "  Conversion rate: ~${conversion_rate}%"
    echo ""

    ((total_noapx_setcc_chains += bench_noapx_patterns))
    ((total_apx_ccmp += bench_apx_ccmp))
done

echo "TOTAL potential CCMP patterns: $total_noapx_setcc_chains"
echo "TOTAL CCMP emitted: $total_apx_ccmp"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 2. NDD CMOV missed opportunities
#    Pattern in non-APX: MOV %regA, %regC followed by CMOVcc %regB, %regC
#    (the MOV sets up the default, CMOV overwrites conditionally)
#    With NDD: CMOVcc %regA, %regB, %regC (no MOV needed)
# ─────────────────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════════════════════"
echo "2. POTENTIAL NDD CMOV PATTERNS (MOV+CMOVcc pairs in non-APX)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

total_noapx_mov_cmov=0
total_apx_ndd_cmov=0

for bench in 505.mcf_r 557.xz_r 525.x264_r 538.imagick_r 502.gcc_r; do
    noapx_dir="$ASMBASE/$bench/noapx"
    apx_dir="$ASMBASE/$bench/apx"
    [ -d "$noapx_dir" ] || continue

    bench_mov_cmov=0
    bench_ndd=0

    for noapx_file in "$noapx_dir"/*.s; do
        [ -f "$noapx_file" ] || continue
        basename=$(basename "$noapx_file")
        apx_file="$apx_dir/$basename"

        # Count 2-operand CMOVcc in non-APX (potential NDD upgrade targets)
        noapx_count=$(grep -cE '^\s+cmov\w+l?\s+%\w+,\s*%\w+$' "$noapx_file" 2>/dev/null) || noapx_count=0
        ((bench_mov_cmov += noapx_count))

        # Count 3-operand NDD CMOVcc in APX
        if [ -f "$apx_file" ]; then
            apx_count=$(grep -cE '^\s+cmov\w+\s+%\w+,\s*%\w+,\s*%\w+' "$apx_file" 2>/dev/null) || apx_count=0
            ((bench_ndd += apx_count))
        fi
    done

    echo "$bench:"
    echo "  Non-APX 2-operand CMOVcc: $bench_mov_cmov"
    echo "  APX 3-operand NDD CMOVcc: $bench_ndd"
    echo "  Remaining 2-op CMOVcc in APX (not upgraded):"
    remaining=0
    for apx_file in "$apx_dir"/*.s; do
        [ -f "$apx_file" ] || continue
        c=$(grep -cE '^\s+cmov\w+l?\s+%\w+,\s*%\w+$' "$apx_file" 2>/dev/null) || c=0
        ((remaining += c))
    done
    echo "    $remaining"
    echo ""

    ((total_noapx_mov_cmov += bench_mov_cmov))
    ((total_apx_ndd_cmov += bench_ndd))
done

echo "TOTAL non-APX 2-op CMOVcc: $total_noapx_mov_cmov"
echo "TOTAL APX NDD CMOVcc: $total_apx_ndd_cmov"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 3. PUSH2/POP2 missed opportunities
#    Pattern: consecutive PUSHQ/POPQ that weren't paired into PUSH2/POP2
# ─────────────────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════════════════════"
echo "3. PUSH/POP PAIRING ANALYSIS"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

for bench in 505.mcf_r 557.xz_r 525.x264_r 538.imagick_r 502.gcc_r; do
    noapx_dir="$ASMBASE/$bench/noapx"
    apx_dir="$ASMBASE/$bench/apx"
    [ -d "$noapx_dir" ] || continue

    noapx_pushq=0
    apx_pushq=0
    apx_push2=0

    for noapx_file in "$noapx_dir"/*.s; do
        [ -f "$noapx_file" ] || continue
        c=$(grep -cE '^\s+pushq\s' "$noapx_file" 2>/dev/null) || c=0
        ((noapx_pushq += c))
    done

    for apx_file in "$apx_dir"/*.s; do
        [ -f "$apx_file" ] || continue
        c=$(grep -cE '^\s+pushq\s' "$apx_file" 2>/dev/null) || c=0
        ((apx_pushq += c))
        c=$(grep -cE '^\s+push2' "$apx_file" 2>/dev/null) || c=0
        ((apx_push2 += c))
    done

    # Each push2 replaces 2 pushq, so total original pushes = apx_pushq + (apx_push2 * 2)
    reconstructed=$((apx_pushq + apx_push2 * 2))
    unpaired=$apx_pushq
    if [ "$reconstructed" -gt 0 ]; then
        pair_rate=$(( (apx_push2 * 2 * 100) / reconstructed ))
    else
        pair_rate=0
    fi

    echo "$bench:"
    echo "  Non-APX individual pushq: $noapx_pushq"
    echo "  APX push2p: $apx_push2 (replaces $((apx_push2 * 2)) pushq)"
    echo "  APX remaining unpaired pushq: $unpaired"
    echo "  Pairing rate: ~${pair_rate}%"
    echo ""
done
