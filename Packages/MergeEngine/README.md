# MergeEngine

A Swift package for line-based two-way diffs, diffs within lines, and three-way
merges. The comparison and merge code is taken from the Perforce P4 sources
(release 2025.1). Apart from two small additions, it is vendored unchanged; see
[VENDORING.md](VENDORING.md). Inputs are byte buffers in memory, and no text
encoding is assumed.

The package contains:

- `MergeEngine`: the Swift library.
- `mergecli`: a command-line tool for running the engine on files.
- `CMergeEngine`: the vendored engine, its adapter, and a C interface. It is an
  internal target.

Requirements: macOS 27 or later, Swift 6.2 or later.

## Building and testing

```bash
swift build
swift test
```

When git is installed, the tests compare merges with `git merge-file`.

## Usage

### Two-way diff

```swift
import MergeEngine

let diff = try Diff(old, new, whitespace: .ignoreAmount)
for block in diff.blocks where block.kind == .changed {
    let removed = diff.a.bytes(lines: block.a.lines)
    let added = diff.b.bytes(lines: block.b.lines)
}
```

The blocks cover both inputs in order and alternate between `.equal` and
`.changed`. Each block has a `Span` per side, with the line indices and the byte
range of the lines.

`Whitespace` selects how lines are compared:

- `.exact`: lines are equal only if their bytes are identical.
- `.ignoreLineEndings` (`-dl`): LF, CRLF and CR endings are equal.
- `.ignoreAmount` (`-db`): runs of spaces and tabs are equal regardless of their
  length, and trailing whitespace is ignored.
- `.ignoreAll` (`-dw`): spaces and tabs are ignored.

The modes other than `.exact` also end a line at a lone CR, so line numbers
depend on the mode. Take line positions from the result (`diff.a`, `diff.b`).

### Changes within a line

```swift
let words = try TokenDiff(oldLine, newLine, granularity: .words)
for block in words.changes {
    let highlighted = block.b.byteRange  // in newLine
}
```

`TokenDiff` has the same shape as `Diff`, with tokens in place of lines. A token
is a run of one character class (letters and digits, whitespace, punctuation,
line endings) by default. With `granularity: .words`, a token is a word together with the single
whitespace byte that follows it. Tokens are compared byte for byte.

### Three-way merge

```swift
let merge = try Merge(base: base, a: theirs, b: mine)
for (index, block) in merge.blocks.enumerated() {
    // block.kind: .unchanged, .changedInA, .changedInB, .changedInBoth, .conflict
    // block.base, block.a, block.b: where the block lies in each input
}

let output = merge.result(resolutions: [1: .b])        // nil while a conflict is open
let marked = merge.result(markingConflicts: .diff3)    // conflict markers, B first as in Git
let text = output?.data
let third = output?.blockRanges[2]                     // block 2's bytes in text
```

`a` is the incoming side (Perforce "theirs") and `b` the own side (Perforce
"yours"). A resolution is a `Merge.Source` (`.base`, `.a`, `.b`, `.aThenB` or
`.bThenA`) and chooses the text of a block. A block without a resolution uses
its `defaultSource`: the side that changed it, or B if neither side changed it
or both made the same change. A conflict has no default, so `result` returns
`nil` until every conflict is resolved. `blockRanges` gives the byte range of
each block in the result, for example to highlight it in an editor.

`MergeStrategy` selects the Perforce merge grid:

- `.optimal` (default): the Perforce default.
- `.guarded` (`-dg`): reports a conflict where the default accepts changes that
  touch the same region.
- `.diff3` (`-dx`): resolves some ambiguous insertions as `diff3` does.
- `.guardedDiff3` (`-dgx`): `.guarded` and `.diff3` combined.
- `.twoWay` (`-dt`): merges as if the base were empty.

## Command line

```bash
swift run mergecli diff [-dl|-db|-dw] [--tokens] old.txt new.txt
swift run mergecli merge [-dl|-db|-dw] [--strategy <name>] [--style diff3|merge] \
    [-q] base.txt theirs.txt mine.txt [-o result.txt]
```

- `diff` lists the changed blocks. `--tokens` also shows the changes within
  each changed line.
- `merge` lists the blocks and the number of conflicts. With `-o`, it writes the
  result with conflict markers; `-o -` writes to standard output. `--strategy`
  takes the names of the `MergeStrategy` cases. `--style` selects the marker
  style, `diff3` by default. `-q` suppresses the listing.

The exit status is 0 without differences or conflicts, 1 with them, and 2 on
errors.

## Behavior

These follow from the Perforce engine and differ from tools such as Git:

- Changes from both sides to adjacent lines merge without a conflict.
- Overlapping changes that share lines are split into separate conflicts around
  the common lines, which become `.changedInBoth` blocks.
- With a whitespace mode other than `.exact`, the sides of an unchanged block
  or an identical change can differ in whitespace or line endings. The result
  takes B's text, as `diffmerge.h` documents; `DiffMerge::Read()` itself
  outputs the base or A there. A resolution can pick another side.
- With `.ignoreLineEndings`, a last line without a line ending equals the same
  line ending in LF or CR, but not one ending in CRLF.

## Memory

`Diff`, `TokenDiff` and `Merge` keep the input `Data` without copying it. Only a
slice that does not start at index 0 is copied. Each input adds 8 bytes per line
or token for its offset table. `result` allocates the merged text once. An input of 2 GiB or more is rejected
with `EngineError.inputTooLarge`. How the vendored code handles allocation
failures is described in [VENDORING.md](VENDORING.md#memory).

## License

The code in this package is available under the MIT license, see
[`LICENSE`](../../LICENSE). The vendored Perforce code is distributed under the
BSD-2-Clause-style Perforce license in
[`Sources/CMergeEngine/Vendor/Perforce/LICENSE`](Sources/CMergeEngine/Vendor/Perforce/LICENSE).
Binary distributions must reproduce its copyright notice, for example in an
application's acknowledgements.
