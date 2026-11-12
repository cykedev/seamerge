# Vendored code

`Sources/CMergeEngine/Vendor/Perforce/` contains a subset of the Perforce P4
command-line and API sources. `Sources/CMergeEngine/Adapter/` and
`Sources/CMergeEngine/Bridge/` are written for this package. They provide the
interfaces the vendored code includes and a C interface over it.

| | |
|---|---|
| Source | Perforce P4 source archive `p4source-2025.1.3079941`, public at `https://ftp.perforce.com/perforce/r25.1/bin.tools/p4source.tgz` |
| SHA-256 | `a823bb865764120d3ca7c3f11168e7381929d77db93588e4e577002f105f68b0` |
| Version | `RELEASE = 2025 1`, `PATCHLEVEL = 3079941`, `SUPPDATE = 2026 09 28` (the archive's `Version` file) |
| License | BSD-2-Clause style, `Vendor/Perforce/LICENSE`, copied unchanged |

Apart from the two changes described below, every vendored file is byte-identical
to the file in the archive. The changed files are `diff/diffmerge.cc` and
`diff/diffmerge.h`.

## Files

| Vendored path | Original path | Changes |
|---|---|---|
| `diff/diff.h` | `diff/diff.h` | none |
| `diff/diffan.cc`, `diff/diffan.h` | same | none |
| `diff/diffflags.cc` | same | none |
| `diff/diffmerge.cc`, `diff/diffmerge.h` | same | two changes, see below |
| `diff/diffsp.cc`, `diff/diffsp.h` | same | none |
| `diff/diffsr.cc`, `diff/diffsr.h` | same | none |
| `sys/stdhdrs.h` | same | none |
| `sys/readfile.h` | same | none |
| `sys/sanitizers.h`, `sys/malloc_override.h` | same | none (included by `stdhdrs.h`) |
| `LICENSE` | `LICENSE` | none |

`Vendor/.clang-format` is not part of the archive. It turns formatting off for
the vendored tree, so the files keep their original layout.

Not vendored:

- `sys/readfile.cc`: replaced by `Adapter/MemoryReadFile.cc`, see below.
- `diff/diff.cc`: the text output formats, such as unified and context output.
  They write to `FILE *`; the Swift layer works on blocks instead.
- `diff/diffmulti*.cc`: N-way diffs.
- The rest of `support/` and `sys/`: the parts the engine needs are replaced by
  the adapter.

## Changes to vendored files

The complete changes are in [`Patches/perforce-diffmerge.patch`](Patches/perforce-diffmerge.patch),
a unified diff against the archive files. In the source they are marked with
`MergeEngine` in a comment.

### `DiffMerge::NextChunk()` (addition)

`DiffMerge::Read()` produces the merged text as a stream, and for unchanged
chunks it outputs only one input's text. It is therefore not possible to learn
from `Read()` where a chunk lies in base, A and B, which is what a merge user
interface needs. `NextChunk()` makes the same single `DiffDiff()` call that
`Read()` makes per chunk and returns the chunk type together with the line
ranges in all three inputs.

The range bookkeeping is in `DiffFfile`, which is private to `diffmerge.cc`, so
the method has to be added there. The tests verify that the blocks built from
`NextChunk()` reproduce the output of the unchanged `Read()` exactly, for every
fixture, comparison mode and strategy, and for random inputs
(`ReadConsistencyTests`).

### `DiffMerge::gridType` initialization (bug fix)

The `DiffMerge` constructor sets `gridType` in every case of its switch on the
grid flag except `DiffFlags::Diff3` (`-dx`), which sets only `diff3behavior`.
For that case `gridType` stays uninitialized. When the uninitialized value
happens to equal `GRT_TWOWAY`, `DiffDiff()` applies the two-way grid to a real
base, returns `BOTH` without advancing, and `Read()` never returns `DD_EOF`. The
constructor now initializes `gridType` to `GRT_OPTIMAL` before the switch, so the
`-dx` case uses the optimal grid, which `MergeStrategy.diff3` documents.
Reproducer: the `merge-delete-vs-edit` fixture with `MergeStrategy.diff3`.

## Adapter

`Sources/CMergeEngine/Adapter/` provides the Perforce interfaces the vendored
code includes, reduced to what it uses:

| File | Replaces | Provides |
|---|---|---|
| `error.h` | `support/error.h` | `Error::Test()` and `Error::Sys()`; the engine only reports allocation failures |
| `strbuf.h` | `support/strbuf.h` | `StrPtr::Text()`, used by `DiffFlags::Init(const StrPtr *)` |
| `debug.h`, `Adapter.cc` | `support/debug.h` | `p4debug` with trace level 0 |
| `tunable.h` | `support/tunable.h` | `p4tunable` with the four tunables the engine reads, fixed at their 2025.1 defaults from `support/debug.cc`: `diff.slimit1` 10000000, `diff.slimit2` 100000000, `diff.sthresh` 50000, `merge.dl.endeol` 0 |
| `filesys.h` | `sys/filesys.h` | `FileSys` as a non-owning view of a byte buffer |
| `MemoryReadFile.cc` | `sys/readfile.cc` | the `ReadFile` class from the unchanged `readfile.h`, reading from memory |

The original `ReadFile` reads files through `mmap(2)` or `read(2)` in windows.
`MemoryReadFile.cc` makes the whole input buffer the window, which is the state
the original reaches after a successful `mmap(2)`. The inline methods in
`readfile.h` behave the same in both cases.

## Memory

The vendored code allocates with `new` and does not use smart pointers. If an
allocation fails, the engine reports `ME_ERROR_OUT_OF_MEMORY`. Objects that were
already allocated can be lost in that case, because the vendored code is not
exception-safe at these points. For example, the constructor of `DiffMerge`
(`diff/diffmerge.cc`, the raw `new` calls for `bf`, `lf1`, `lf2`, `df1`, `df2` and
`df3`) can leak the earlier allocations if a later one fails. This is known and
deliberately not patched, to keep the vendored code close to the release.

The line tables are the exception: `Sequence::GrowLineBuf()` catches
`std::bad_alloc` and reports it through `Error`, and the C interface maps the
failure to `ME_ERROR_OUT_OF_MEMORY` (`Bridge/Bridge.cc`).

## Updating

1. Copy the files in the table from the new release.
2. Apply `Patches/perforce-diffmerge.patch` with `patch -p1` in
   `Vendor/Perforce` and resolve any rejects.
3. Check whether the engine now uses further tunables, debug types, or `Error`
   and `FileSys` members, and extend the adapter. Names the adapter does not
   define fail to compile.
4. Run `swift test`. `ReadConsistencyTests` and `GitComparisonTests` show
   changes in the engine's behavior.
5. Update the version and the checksum above.
