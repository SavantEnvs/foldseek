# foldcomp: `&vec[0]` on an empty vector while reading a truncated `.fcz`

Reproducer: `crash-empty-vector` (5 bytes, `FCMP` magic plus one byte). Run
`/mayhem/fuzz_foldcomp-standalone crash-empty-vector`.

- Path: `GemmiWrapper::loadFromBuffer` -> `loadFoldcompStructure` (`src/strucclustutils/GemmiWrapper.cpp`)
  -> `Foldcomp::read` (`lib/foldcomp/src/foldcomp.cpp`, around line 922).
- Cause: `read()` sizes a vector from header fields of the (truncated) file, which come out as 0, and then
  passes `&vec[0]` to `istream::read`. Taking the address of element 0 of an empty `std::vector` is
  undefined behavior (UBSan: reference binding to null pointer).
- Impact: undefined behavior on a malformed `.fcz` file that `foldseek createdb` accepts as input. No memory is
  written; it only aborts under UBSan.
- Fix: use `vec.data()` and reject the file when the computed size is 0.

The reproducer is kept out of `testsuite/` because seeds are replayed on every run.
