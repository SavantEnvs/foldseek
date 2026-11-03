# Mayhem defects with no backtrace: triage noise, not foldseek bugs

Some `fuzz-mmcif`, `fuzz-chemcomp` and `fuzz-mmjson` runs list an "Uncategorized Defect" (medium, CWE none)
with an empty `parsed_backtrace`. A new one appears in each run and each is a different input, so they do not
group. Examples (run 4 at `630feaa`): `fuzz-mmcif` #3551747, `fuzz-chemcomp` #3551757, `fuzz-mmjson` #3551777;
run 5: `fuzz-mmcif` #3569576.

The recorded output of every one ends the same way, with no sanitizer report:

```
Executed /triager_scratch_space/<sha256> in 0 ms
Error: Continue after stop failed
    ESRCH: No such process
Stack backtrace: anyhow::error::From::from, ptracer::do_parent, ptracer::main, ...
```

`ptracer` is Mayhem's triage tool. It failed to resume a traced process that had already finished; the target
itself ran the input and returned. Evidence that the input is not a foldseek defect:

- Replaying the saved inputs (`#3551747` -> `54f6fc24...`, `#3551757` -> `45161983...`, `#3551777` ->
  `8ce25c07...`, `#3569576` -> `07c84e2c...`) in the deployed image: 100 runs each of `/mayhem/<target>` and
  `/mayhem/<target>-standalone`, 800 runs in all. Every run exits 0 with no sanitizer output, so the result is
  not input-dependent.
- A real defect in these parsers does reproduce and gets a frame: `fuzz-mmcif` #3541383/#3520511 are
  `gemmi::string_to_int` at `lib/gemmi/atox.hpp:87` (signed overflow), `fuzz-pdb`/`fuzz-createdb-3di` have the
  `fast_float` `fastfloat_strncasecmp` out-of-bounds read.
- The harness holds no state across inputs (`GemmiWrapper` and the createdb objects are locals per call), so a
  replay in isolation is the same as the fuzz-time execution.

Treat a frameless defect whose output ends in `ptracer ... ESRCH` as a triage failure. If one reproduces with
`/mayhem/<target>-standalone <input>` it is a real defect and gets a write-up here.
