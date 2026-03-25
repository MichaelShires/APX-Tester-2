#!/bin/zsh
# Compile SPEC benchmarks with -mapxf AND +cf (conditional faulting).
# Outputs to SPEC/asm/{benchmark}/apx_cf/

set -uo pipefail

CLANG="/opt/homebrew/opt/llvm/bin/clang"
TARGET="x86_64-apple-macos"
SYSROOT=$(xcrun --sdk macosx --show-sdk-path)
OPT="-O2"
SPECBASE="SPEC/benchmarks/benchspec/CPU"
ASMBASE="SPEC/asm"

compile_benchmark() {
    local bench="$1"
    local cflags="$2"
    local srcdir="$SPECBASE/$bench/src"

    echo "=== Compiling $bench (APX + CF) ==="

    local cf_dir="$ASMBASE/$bench/apx_cf"
    mkdir -p "$cf_dir"

    local count=0
    local failed=0

    for cfile in $(find "$srcdir" -name "*.c"); do
        local relpath="${cfile#$srcdir/}"
        local asmname="${relpath//\//_}"
        asmname="${asmname%.c}.s"

        if $CLANG -S --target="$TARGET" -isysroot "$SYSROOT" $OPT -mapxf \
            -Xclang -target-feature -Xclang +cf \
            ${=cflags} \
            -w -Wno-everything \
            -I"$srcdir" \
            -o "$cf_dir/$asmname" "$cfile" 2>/dev/null; then
            ((count++)) || true
        else
            ((failed++)) || true
        fi
    done

    echo "  Compiled $count files successfully ($failed failed)"
}

compile_benchmark "505.mcf_r" "-I$SPECBASE/505.mcf_r/src/spec_qsort -DSPEC_AUTO_SUPPRESS_OPENMP"
compile_benchmark "557.xz_r" "-I$SPECBASE/557.xz_r/src/common -I$SPECBASE/557.xz_r/src/liblzma/api -I$SPECBASE/557.xz_r/src/liblzma/check -I$SPECBASE/557.xz_r/src/liblzma/common -I$SPECBASE/557.xz_r/src/liblzma/delta -I$SPECBASE/557.xz_r/src/liblzma/lz -I$SPECBASE/557.xz_r/src/liblzma/lzma -I$SPECBASE/557.xz_r/src/liblzma/rangecoder -I$SPECBASE/557.xz_r/src/liblzma/simple -DSPEC_AUTO_SUPPRESS_OPENMP -DHAVE_CONFIG_H -DSPEC_MEM_IO"
compile_benchmark "525.x264_r" "-I$SPECBASE/525.x264_r/src/x264_src -I$SPECBASE/525.x264_r/src/x264_src/common -I$SPECBASE/525.x264_r/src/x264_src/extras -DSPEC_AUTO_SUPPRESS_OPENMP -DSPEC"
compile_benchmark "538.imagick_r" "-I$SPECBASE/538.imagick_r/src -I$SPECBASE/538.imagick_r/src/MagickCore -I$SPECBASE/538.imagick_r/src/MagickWand -DSPEC_AUTO_SUPPRESS_OPENMP -DSPEC"
compile_benchmark "502.gcc_r" "-I$SPECBASE/502.gcc_r/src -I$SPECBASE/502.gcc_r/src/include -I$SPECBASE/502.gcc_r/src/config -I$SPECBASE/502.gcc_r/src/config/i386 -I$SPECBASE/502.gcc_r/src/spec_qsort -DSPEC_AUTO_SUPPRESS_OPENMP -DSPEC -DIN_GCC -DHAVE_CONFIG_H"

echo ""
echo "=== Scanning for CFCMOV instructions ==="
echo ""

total_cfcmov=0
total_cfcmov_files=0

for bench in 505.mcf_r 557.xz_r 525.x264_r 538.imagick_r 502.gcc_r; do
    cf_dir="$ASMBASE/$bench/apx_cf"
    apx_dir="$ASMBASE/$bench/apx"

    bench_cfcmov=0
    bench_cfcmov_files=0
    bench_ccmp=0
    bench_ctest=0
    bench_ndd=0
    bench_push2=0
    bench_pop2=0

    for f in "$cf_dir"/*.s; do
        [ -f "$f" ] || continue

        c=$(grep -cE '^\s+cfcmov' "$f" 2>/dev/null) || c=0
        if [ "$c" -gt 0 ]; then
            ((bench_cfcmov_files++))
        fi
        ((bench_cfcmov += c))

        c=$(grep -cE '^\s+ccmp' "$f" 2>/dev/null) || c=0
        ((bench_ccmp += c))

        c=$(grep -cE '^\s+ctest' "$f" 2>/dev/null) || c=0
        ((bench_ctest += c))

        c=$(grep -cE '^\s+cmov\w+\s+%\w+,\s*%\w+,\s*%\w+' "$f" 2>/dev/null) || c=0
        ((bench_ndd += c))

        c=$(grep -cE '^\s+push2' "$f" 2>/dev/null) || c=0
        ((bench_push2 += c))

        c=$(grep -cE '^\s+pop2' "$f" 2>/dev/null) || c=0
        ((bench_pop2 += c))
    done

    # Get the corresponding counts from apx-only (no cf)
    apx_ccmp=0; apx_ctest=0; apx_ndd=0; apx_push2=0; apx_pop2=0
    for f in "$apx_dir"/*.s; do
        [ -f "$f" ] || continue
        c=$(grep -cE '^\s+ccmp' "$f" 2>/dev/null) || c=0; ((apx_ccmp += c))
        c=$(grep -cE '^\s+ctest' "$f" 2>/dev/null) || c=0; ((apx_ctest += c))
        c=$(grep -cE '^\s+cmov\w+\s+%\w+,\s*%\w+,\s*%\w+' "$f" 2>/dev/null) || c=0; ((apx_ndd += c))
        c=$(grep -cE '^\s+push2' "$f" 2>/dev/null) || c=0; ((apx_push2 += c))
        c=$(grep -cE '^\s+pop2' "$f" 2>/dev/null) || c=0; ((apx_pop2 += c))
    done

    echo "--- $bench ---"
    echo "  CFCMOV:    $bench_cfcmov (in $bench_cfcmov_files files)  [NEW with +cf]"
    echo "  CCMP:      $bench_ccmp  (was $apx_ccmp without +cf)"
    echo "  CTEST:     $bench_ctest"
    echo "  NDD CMOV:  $bench_ndd  (was $apx_ndd without +cf)"
    echo "  PUSH2:     $bench_push2  (was $apx_push2 without +cf)"
    echo "  POP2:      $bench_pop2  (was $apx_pop2 without +cf)"
    echo ""

    ((total_cfcmov += bench_cfcmov))
    ((total_cfcmov_files += bench_cfcmov_files))
done

echo "================================================================================"
echo "TOTAL CFCMOV with +cf: $total_cfcmov (across $total_cfcmov_files files)"
echo "================================================================================"
