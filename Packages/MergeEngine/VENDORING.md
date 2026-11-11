# Vendored code

`Sources/CMergeEngine/Vendor/Perforce/` contains a subset of the Perforce P4
command-line and API sources.

| | |
|---|---|
| Source | Perforce P4 source archive `p4source-2025.1.3079941` |
| Version | `RELEASE = 2025 1`, `PATCHLEVEL = 3079941`, `SUPPDATE = 2026 09 28` |
| License | BSD-2-Clause style, `Vendor/Perforce/LICENSE` (copied unchanged) |

All files keep their copyright headers and original formatting
(`Vendor/.clang-format` disables formatting).

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

Not vendored:

- `sys/readfile.cc`: replaced by `Adapter/MemoryReadFile.cc`, see below.
- `diff/diff.cc`: the text output formats (unified, context, RCS, HTML).
  They write to `FILE *`; the Swift layer works on blocks instead.
- `diff/diffmulti*.cc`: N-way diffs.
- Everything else in `support/` and `sys/`; the parts the engine needs are
  replaced by the adapter.

## Changes to vendored files

The complete changes are in [`Patches/perforce-diffmerge.patch`](Patches/perforce-diffmerge.patch),
a unified diff against the original files. In the source they are marked with
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

The `DiffMerge` constructor sets `gridType` for every grid flag except
`DiffFlags::Diff3` (`-dx`), which leaves it uninitialized. When the
uninitialized value happens to equal `GRT_TWOWAY`, `DiffDiff()` applies the
two-way grid to a real base, returns `BOTH` without advancing, and `Read()`
never returns `DD_EOF`. The constructor now initializes `gridType` to
`GRT_OPTIMAL` before the switch, which is the grid `-dx` is documented to use.
Reproducer: the `merge-delete-vs-edit` fixture with `MergeStrategy.diff3`.

## Adapter

`Sources/CMergeEngine/Adapter/` is code written for this package. It provides
the Perforce interfaces the vendored code includes, reduced to what it uses:

| File | Replaces | Provides |
|---|---|---|
| `error.h` | `support/error.h` | `Error::Test()` and `Error::Sys()`; the engine only reports allocation failures |
| `strbuf.h` | `support/strbuf.h` | `StrPtr::Text()`, used by `DiffFlags::Init(const StrPtr *)` |
| `debug.h`, `Adapter.cc` | `support/debug.h` | `p4debug` with trace level 0 |
| `tunable.h` | `support/tunable.h` | `p4tunable` with the four tunables the engine reads, fixed at their 2025.1 defaults from `support/debug.cc` |
| `filesys.h` | `sys/filesys.h` | `FileSys` as a non-owning view of a byte buffer |
| `MemoryReadFile.cc` | `sys/readfile.cc` | the `ReadFile` class from the unchanged `readfile.h`, reading from memory |

The original `ReadFile` reads files through `mmap(2)` or `read(2)` in windows.
`MemoryReadFile.cc` makes the whole input buffer the window, which is the state
the original reaches after a successful `mmap(2)`; the inline methods in
`readfile.h` behave the same in both cases.

## Memory

The vendored code allocates with `new` and does not use smart pointers. Its
allocations fall into two groups:

- The line tables, which grow with the input. `Sequence::GrowLineBuf()`
  catches `std::bad_alloc` and reports it through `Error`; the C interface
  returns `ME_ERROR_OUT_OF_MEMORY` and releases everything.
- Individually small allocations: the line readers, the nodes of the list of
  matching runs, and the two search vectors of `DiffAnalyze`, which hold at
  most 20,001 `int` each. These are not exception-safe. If one of them
  throws, the C interface also returns `ME_ERROR_OUT_OF_MEMORY`, but the
  objects built so far are not released.

On macOS, an allocation of that size fails only when the process has run out
of memory altogether. Swift code stops with a runtime error in that state
anyway, because the Swift standard library does not recover from allocation
failures. Making the vendored constructors exception-safe would change a large
part of the code for no practical gain, so they are left as they are.

## Updating

1. Copy the files in the table from the new release.
2. Apply `Patches/perforce-diffmerge.patch` (`patch -p1` in `Vendor/Perforce`)
   and resolve any rejects.
3. Check whether the engine now uses further tunables, debug types or `Error`
   and `FileSys` members, and extend the adapter. Unknown names fail the build.
4. Run `swift test`. `ReadConsistencyTests` and `GitComparisonTests` show
   changes in the engine's behavior.
5. Update the version above.
