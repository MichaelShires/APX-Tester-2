#!/bin/zsh
# Compile SPEC benchmark source files to assembly with and without APX flags.
# Usage: ./scripts/compile_spec.sh
#
# Outputs assembly files to SPEC/asm/{benchmark}/{apx|noapx}/

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

    echo "=== Compiling $bench ==="

    local apx_dir="$ASMBASE/$bench/apx"
    local noapx_dir="$ASMBASE/$bench/noapx"
    mkdir -p "$apx_dir" "$noapx_dir"

    local count=0
    local failed=0

    for cfile in $(find "$srcdir" -name "*.c"); do
        local relpath="${cfile#$srcdir/}"
        local asmname="${relpath//\//_}"
        asmname="${asmname%.c}.s"

        # With APX
        if $CLANG -S --target="$TARGET" -isysroot "$SYSROOT" $OPT -mapxf ${=cflags} \
            -w -Wno-everything \
            -I"$srcdir" \
            -o "$apx_dir/$asmname" "$cfile" 2>/dev/null; then
            : # success
        else
            ((failed++)) || true
            continue
        fi

        # Without APX
        if $CLANG -S --target="$TARGET" -isysroot "$SYSROOT" $OPT ${=cflags} \
            -w -Wno-everything \
            -I"$srcdir" \
            -o "$noapx_dir/$asmname" "$cfile" 2>/dev/null; then
            : # success
        else
            rm -f "$apx_dir/$asmname"
            ((failed++)) || true
            continue
        fi

        ((count++)) || true
    done

    echo "  Compiled $count files successfully ($failed failed)"
}

compile_benchmark "505.mcf_r" "-I$SPECBASE/505.mcf_r/src/spec_qsort -DSPEC_AUTO_SUPPRESS_OPENMP"
compile_benchmark "557.xz_r" "-I$SPECBASE/557.xz_r/src/common -I$SPECBASE/557.xz_r/src/liblzma/api -I$SPECBASE/557.xz_r/src/liblzma/check -I$SPECBASE/557.xz_r/src/liblzma/common -I$SPECBASE/557.xz_r/src/liblzma/delta -I$SPECBASE/557.xz_r/src/liblzma/lz -I$SPECBASE/557.xz_r/src/liblzma/lzma -I$SPECBASE/557.xz_r/src/liblzma/rangecoder -I$SPECBASE/557.xz_r/src/liblzma/simple -DSPEC_AUTO_SUPPRESS_OPENMP -DHAVE_CONFIG_H -DSPEC_MEM_IO"
compile_benchmark "525.x264_r" "-I$SPECBASE/525.x264_r/src/x264_src -I$SPECBASE/525.x264_r/src/x264_src/common -I$SPECBASE/525.x264_r/src/x264_src/extras -DSPEC_AUTO_SUPPRESS_OPENMP -DSPEC"
compile_benchmark "538.imagick_r" "-I$SPECBASE/538.imagick_r/src -I$SPECBASE/538.imagick_r/src/MagickCore -I$SPECBASE/538.imagick_r/src/MagickWand -DSPEC_AUTO_SUPPRESS_OPENMP -DSPEC"
compile_benchmark "502.gcc_r" "-I$SPECBASE/502.gcc_r/src -I$SPECBASE/502.gcc_r/src/include -I$SPECBASE/502.gcc_r/src/config -I$SPECBASE/502.gcc_r/src/config/i386 -I$SPECBASE/502.gcc_r/src/spec_qsort -DSPEC_AUTO_SUPPRESS_OPENMP -DSPEC -DIN_GCC -DHAVE_CONFIG_H"

echo ""
echo "=== Assembly output summary ==="
for bench in 505.mcf_r 557.xz_r 525.x264_r 538.imagick_r 502.gcc_r; do
    apx_count=$(ls "$ASMBASE/$bench/apx/"*.s 2>/dev/null | wc -l | tr -d ' ')
    noapx_count=$(ls "$ASMBASE/$bench/noapx/"*.s 2>/dev/null | wc -l | tr -d ' ')
    echo "  $bench: $apx_count APX / $noapx_count non-APX assembly files"
done
