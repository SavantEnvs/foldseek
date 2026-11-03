# fuzz_zstd_structure: known findings

Replay with `/mayhem/fuzz_zstd_structure-standalone <file>` (the first byte picks PDB or mmCIF, the rest is
the zstd stream). Kept out of `testsuite/` because seeds are replayed on every run.

- `crash-frame-content-size-alloc`: `decompressZstdBuffer` (`src/strucclustutils/GemmiWrapper.cpp:38`) does
  `new char[ZSTD_getFrameContentSize(...)]` with the size the frame header declares, before decompressing
  anything. A 24-byte file can request terabytes. Every Mayhem defect at `GemmiWrapper.cpp:38` is this one
  cause (OOM class). Fix: cap the declared size, or fall through to the streaming path above a limit.
- `crash-zstd-null-pointer-arith`: UBSan "applying non-zero offset to null pointer" in
  `ZSTD_decompressSequencesLong_body` of the bundled (old) zstd, reached from `ZSTD_decompress`. A separate
  cause in the vendored library; Mayhem files it as an out-of-bounds read.

Asymmetry with the other six zstd targets (`fuzz_zstd_*` over zstd's own `tests/fuzz` harnesses): their zstd
objects are built with `-fno-sanitize=pointer-overflow` (see `mayhem/build.sh`), because the same old-zstd
`NULL + n` arithmetic would trip UBSan on the first empty input of every compress-side target. The foldseek
build that `fuzz_zstd_structure` links keeps that check on. So the `crash-zstd-null-pointer-arith` cause is
reported only here; a zero-defect result on the six zstd-only targets does not mean the bundled zstd is clean
of it.
