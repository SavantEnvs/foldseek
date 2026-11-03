# fuzz_foldcomp: known findings in `lib/foldcomp` (one cause, several symptoms)

Everything `fuzz_foldcomp` (and the `.fcz` branch of `fuzz_createdb_3di`, before it was pinned to PDB/mmCIF)
reports comes from one missing validation: `Foldcomp::read` takes the header counts (`nResidue`,
`nSideChainTorsion`, `lenTitle`, `nInnerAnchor`, the `anchorIndices` array) from the file and never checks
them against the payload or against each other, and `Foldcomp::decompress` then indexes with them.
The crash sites below are distinct code lines (Mayhem keys defects on the stack), not distinct causes.

Replay any reproducer with `/mayhem/fuzz_foldcomp-standalone <file>`. They are kept out of `testsuite/`
because seeds are replayed on every run. The OOM reproducer needs the libFuzzer binary (2 GB malloc limit):
`/mayhem/fuzz_foldcomp <file>`.

| Site | Class | Reproducer |
| --- | --- | --- |
| `foldcomp.cpp:922` `&anchorIndices[0]` with 0 anchors | null reference (UBSan) | `empty-vector-deref/crash-empty-vector` |
| `foldcomp.cpp:995` `new unsigned char[nSideChainTorsion]`, `:924` `std::string(lenTitle, 0)`, `:1008` `push_back` loop | allocation size from header (OOM class) | `crash-header-size-alloc-995` |
| `foldcomp.cpp:824`/`:825` `&compressedBackBone[firstIndex]` (clamped with `maxIndex = size-1 = -1`) | out-of-range `operator[]` | `crash-compressedBackBone-index-824`, `-825` |
| `foldcomp.cpp:835`/`:836` `anchorIndices[i] * 3` | signed `int` overflow | `crash-anchorIndices-overflow-835`, `-836` |
| `foldcomp.cpp:874` `AAS.at(currResidue)` (residue from header) | uncaught `std::out_of_range` | `crash-AAS-at-out-of-range-874` |
| `foldcomp.cpp:361` `continuizeSideChainTorsionAngles` (`torsionDiscretized[currIndex]`, `currIndex` runs past the vector read from the file), from `foldcomp.cpp:416` | out-of-bounds read / null `operator[]` | `crash-sidechain-torsion-oob-361` |
| `nerf.cpp:145` `reconstructAminoAcid` (side-chain angle vectors shorter than the residue needs) | heap-buffer-overflow / null reference | `crash-sidechain-angles-index-nerf145` |
| `nerf.cpp:367` `reconstructWithReversed` (`torsion_angles[i]`), called from `foldcomp.cpp:266` | heap-buffer-overflow | `crash-reverse-torsion-oob-nerf367` |

Mapping of Mayhem's `std::vector<...>::operator[]` frames, which hide the site below them: `vector<unsigned int>`
is `:361` (null when `torsionDiscretized` is empty, out-of-bounds otherwise), `vector<int>` null is `:922`
`&anchorIndices[0]`, `vector<float>` is `nerf.cpp:145`, `vector<BackboneChain>` is `:824`/`:825`. The
"excessive allocation" defects are `:995`, `:924` and `:1008`.

Impact: a crafted `.fcz` (or a tar entry starting with `FCMP`) passed to `foldseek createdb` aborts the process
or reads out of bounds. Fix: reject the file in `read()` when the header counts are inconsistent with the
file size and each other (anchors, residues, torsions) and use `data()` instead of `&v[0]`.
The mayhem layer cannot patch upstream (additive-only), and the harness cannot pre-filter these inputs
without hiding the bug, so they stay visible in the target.

Throughput: `fuzz-foldcomp` runs at about 17 exec/s on Mayhem (run 4: 6744 tests in 300 s) because the
target keeps crashing, not because an input is slow. Each of the ~60 crashing inputs the server keeps in the
testsuite is replayed on every start and each costs 0.3 to 1.1 s (process start, ASan symbolization, the
multi-GB allocation attempts): in the deployed image the reproducers above take 24 ms (`crash-empty-vector`,
`crash-anchorIndices-overflow-835`, `crash-compressedBackBone-index-825`, `crash-sidechain-angles-index-nerf145`),
~0.3 s (`crash-AAS-at-out-of-range-874`, `crash-compressedBackBone-index-824`, `crash-header-size-alloc-995`,
`crash-reverse-torsion-oob-nerf367`, `crash-sidechain-torsion-oob-361`) and 1.07 s
(`crash-anchorIndices-overflow-836`). Fixing the missing header validation in `Foldcomp::read` would remove
these crashers. Pre-filtering them in the harness would hide the bug.
