#!/usr/bin/env bash
#
# mayhem/test.sh — known-answer checks on the normally-built foldseek (mayhem/build.sh builds it).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

FS="$SRC/mayhem/build-oracle/src/foldseek"
if [ ! -x "$FS" ]; then echo "missing $FS: mayhem/build.sh did not build it" >&2; emit_ctrf "foldseek-known-answer" 0 1 0; exit 1; fi

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
cd "$W"

passed=0; failed=0
check() {
  if [ "$2" = "$3" ]; then passed=$((passed+1)); echo "ok   $1"
  else failed=$((failed+1)); echo "FAIL $1: got [$2] want [$3]"; fi
}
seqs() { grep -v '^>' "$1" 2>/dev/null | tr -d '\n'; }

D1ASHA_AA=ANKTRELCMKSLEHAKVDTSNEARQDGIDLYKHMFENYPPLRKYFKSREEYTAEDVQNDPFFAKQGQKILLACHVLCATYDDRETFNAYTRELLDRHARDHVHMPPEVWTDFWKLFEEYLGKKTTLDEPTKQAWHEIGREFAKEINK
D1ASHA_3DI=DVVLLVLQLVLVVLADLDDDVSNLVSLLVLVQLCVQPVLVLLVLVPPCNVPHSVNSVPDSVSSVVSSVVVVLVNVLSNCVVPVVVNLVSLVVVQVVCVVVPSDDDLVVLLVVLVSVVVSSCVRDPRDPVNNVSSVVSSVVSSVSNVD

# PDB file -> sequence DB and 3Di DB
"$FS" createdb "$SRC/example/d1asha_" db >createdb.log 2>&1
"$FS" convert2fasta db aa.fa >/dev/null 2>&1
"$FS" lndb db_h db_ss_h >/dev/null 2>&1
"$FS" convert2fasta db_ss ss.fa >/dev/null 2>&1
check "createdb amino-acid sequence of d1asha_" "$(seqs aa.fa)" "$D1ASHA_AA"
check "createdb 3Di sequence of d1asha_" "$(seqs ss.fa)" "$D1ASHA_3DI"

# gzipped two-chain PDB entry
"$FS" createdb "$SRC/example/1tim.pdb.gz" tim >createdb_tim.log 2>&1
"$FS" convert2fasta tim tim.fa >/dev/null 2>&1
"$FS" lndb tim_h tim_ss_h >/dev/null 2>&1
"$FS" convert2fasta tim_ss tim_ss.fa >/dev/null 2>&1
check "1tim.pdb.gz yields two chains" "$(grep -c '^>' tim.fa 2>/dev/null)" "2"
check "1tim chain A 3Di prefix" "$(sed -n 2p tim_ss.fa 2>/dev/null | cut -c1-30)" "DCLQFEEEEEAPPDDDLVLVLVLQVLVVVL"
check "1tim chain A length" "$(sed -n 2p tim_ss.fa 2>/dev/null | tr -d '\n' | wc -c)" "247"

# structural search of a structure against itself: identical, full-length hit
"$FS" easy-search "$SRC/example/d1asha_" "$SRC/example/d1asha_" aln.m8 tmp --threads 1 >search.log 2>&1
check "self-search hit" "$(awk -F'\t' '{print $1, $2, $3, $4, $5, $6}' aln.m8 2>/dev/null)" "d1asha_ d1asha_ 1.000 147 0 0"
check "self-search bit score" "$(awk -F'\t' '{print $12}' aln.m8 2>/dev/null)" "1064"

emit_ctrf "foldseek-known-answer" "$passed" "$failed" 0
