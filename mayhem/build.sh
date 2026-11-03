#!/usr/bin/env bash
# Builds foldseek's structure-input fuzz surface (GemmiWrapper + the createdb 3Di pipeline, and the
# bundled zstd), plus a normally-built foldseek binary for the test.sh oracle.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export CARGO_HOME="${CARGO_HOME:-/opt/toolchains/rust/cargo}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
FB="$SRC/mayhem/build-fuzz"
OB="$SRC/mayhem/build-oracle"
ZB="$SRC/mayhem/build-zstd"
ZSTD="$SRC/lib/mmseqs/lib/zstd"
mkdir -p "$ZB"

# UBSan relaxation: gemmi's util.hpp left-shifts negative chars (shift-base) on every parse.
# fuzzer-no-link gives the library SanCov edges; it is added even when SANITIZER_FLAGS is empty.
PROJ_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fno-sanitize=shift-base -fsanitize=fuzzer-no-link"
FLAVOR="-DENABLE_PROSTT5=0 -DENABLE_STRUCTTY=0 -DHAVE_TESTS=0 -DHAVE_MPI=0 -DNATIVE_ARCH=0 -DHAVE_SSE4_1=1"

# 1) the project itself, sanitized, DWARF 3
cmake -S "$SRC" -B "$FB" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$PROJ_FLAGS" -DCMAKE_CXX_FLAGS="$PROJ_FLAGS" $FLAVOR
cmake --build "$FB" -j"$MAYHEM_JOBS"

# 2) harnesses: one structure harness source, one binary per FS_MODE
INC=""
for d in lib lib/3di lib/pulchra lib/kerasify src/commons lib/mmseqs/lib/block-aligner/c \
  lib/mmseqs/lib/zstd/lib lib/mmseqs/lib/tinyexpr lib/mmseqs/lib/microtar lib/mmseqs/lib/tantan \
  lib/mmseqs/lib/simde lib/mmseqs/lib lib/mmseqs/lib/simd lib/mmseqs/lib/alp lib/mmseqs/lib/ksw2 \
  lib/mmseqs/lib/xxhash lib/mmseqs/lib/ips4o lib/mmseqs/src/alignment lib/mmseqs/src/clustering \
  lib/mmseqs/src/commons lib/mmseqs/src/multihit lib/mmseqs/src/prefiltering lib/mmseqs/src/linclust \
  lib/mmseqs/src/taxonomy lib/mmseqs/src/util lib/mmseqs/src lib/gemmi lib/foldcomp/src \
  src/strucclustutils; do INC="$INC -I$SRC/$d"; done
INC="$INC -I$FB/generated -I$FB/lib/mmseqs/generated"
DEFS="-DENABLE_IPS4O=1 -DHAVE_BZLIB=1 -DHAVE_POSIX_FADVISE=1 -DHAVE_POSIX_MADVISE=1 -DHAVE_ZLIB=1 -DOPENMP=1 -D_USE_MATH_DEFINES=1"
CXXF="$PROJ_FLAGS -O2 -w -fsigned-char -msse4.1 -mcx16 -std=c++1y -fopenmp=libomp $DEFS $INC"

L="$FB/lib"
LIBS="$FB/src/libfoldseek-framework.a $FB/src/version/libversion.a $FB/src/strucclustutils/libgemmiwrapper.a \
 $L/foldcomp/libfoldcomp.a $L/3di/lib3di.a $L/pulchra/libpulchra.a $L/kerasify/libkerasify.a \
 $L/tmalign/libtmalign.a $L/mmseqs/src/libmmseqs-framework.a $L/mmseqs/lib/tinyexpr/libtinyexpr.a \
 $L/mmseqs/lib/zstd/build/cmake/lib/libzstd.a $L/mmseqs/lib/microtar/libmicrotar.a \
 $L/mmseqs/lib/tantan/libtantan.a $L/mmseqs/libblock_aligner_c.a"
SYSLIBS="-latomic -lutil -lrt -lpthread -lm -ldl -lz -lbz2"

$CXX $CXXF -c mayhem/lsan_off.cc -o "$FB/lsan_off.o"
$CXX $CXXF -c mayhem/fs_globals.cpp -o "$FB/fs_globals.o"
$CC $PROJ_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$FB/standalone_main.o"

build_structure() {
  local name="$1" mode="$2"
  $CXX $CXXF -DFS_MODE="$mode" -c mayhem/fuzz_structure.cpp -o "$FB/$name.o"
  $CXX $PROJ_FLAGS -fopenmp=libomp "$FB/$name.o" "$FB/fs_globals.o" "$FB/lsan_off.o" $LIB_FUZZING_ENGINE \
    -Wl,--start-group $LIBS -Wl,--end-group $SYSLIBS -o "$SRC/$name"
  $CXX $PROJ_FLAGS -fopenmp=libomp "$FB/$name.o" "$FB/fs_globals.o" "$FB/lsan_off.o" "$FB/standalone_main.o" \
    -Wl,--start-group $LIBS -Wl,--end-group $SYSLIBS -o "$SRC/$name-standalone"
}
build_structure fuzz_pdb 1 &
build_structure fuzz_mmcif 2 &
build_structure fuzz_mmjson 3 &
build_structure fuzz_chemcomp 4 &
build_structure fuzz_foldcomp 5 &
build_structure fuzz_zstd_structure 6 &
build_structure fuzz_gzip_structure 7 &
build_structure fuzz_createdb_3di 8 &
wait

# zstd's own libFuzzer harnesses (tests/fuzz), over the bundled zstd sources
ZINC="-I$ZSTD/lib -I$ZSTD/lib/common -I$ZSTD/lib/compress -I$ZSTD/programs -I$ZSTD/tests/fuzz"
# pointer-overflow relaxed for zstd only: the bundled (old) zstd does `NULL + 1`-style pointer arithmetic on empty input,
# which UBSan flags on the very first (empty) libFuzzer execution of every compress-side target.
# The foldseek build itself keeps pointer-overflow on, so fuzz_zstd_structure still reports that arithmetic
# (see mayhem/fuzz_zstd_structure/known-findings): zero defects on the six zstd-only targets is not a clean bill.
ZCF="$PROJ_FLAGS -fno-sanitize=pointer-overflow -O2 -w $ZINC"
zobjs=""
for f in "$ZSTD"/lib/common/*.c "$ZSTD"/lib/compress/*.c "$ZSTD"/lib/decompress/*.c \
  "$ZSTD/programs/util.c" "$ZSTD/tests/fuzz/zstd_helpers.c"; do
  o="$ZB/lib_$(basename "$f" .c).o"; zobjs="$zobjs $o"
  $CC $ZCF -c "$f" -o "$o" &
  while [ "$(jobs -rp | wc -l)" -ge "$MAYHEM_JOBS" ]; do wait -n; done
done
wait
for t in simple_round_trip stream_round_trip block_round_trip simple_decompress stream_decompress block_decompress; do
  $CC $ZCF -c "$ZSTD/tests/fuzz/$t.c" -o "$ZB/$t.o"
  $CXX $PROJ_FLAGS $zobjs "$ZB/$t.o" "$FB/lsan_off.o" $LIB_FUZZING_ENGINE -o "$SRC/fuzz_zstd_$t"
  $CXX $PROJ_FLAGS $zobjs "$ZB/$t.o" "$FB/lsan_off.o" "$FB/standalone_main.o" -o "$SRC/fuzz_zstd_$t-standalone"
done

# 3) the oracle: foldseek itself, normal flags (no sanitizer, no -gdwarf-3)
cmake -S "$SRC" -B "$OB" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" $FLAVOR
cmake --build "$OB" -j"$MAYHEM_JOBS" --target foldseek
