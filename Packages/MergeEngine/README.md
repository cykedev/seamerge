# MergeEngine

A Swift package for line-based two-way diffs and three-way merges, built on the
diff and merge engine from the Perforce P4 sources (release 2025.1). Inputs are
byte buffers in memory; no text encoding is assumed.

The package contains:

- `MergeEngine`: the Swift library.
- `mergecli`: a command-line tool for trying the engine on files.
- `CMergeEngine`: the Perforce engine and its C interface (internal, see
  [VENDORING.md](VENDORING.md)).

Requirements: macOS 27 or later, Swift 6.2 or later.

## Building and testing

```bash
swift build
swift test
```

The tests compare merges with `git merge-file` when git is installed.

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
`.changed`. Each block has a `Span` per side with line indices and byte offsets.

`Whitespace` selects how lines are compared: `.exact`, `.ignoreLineEndings`
(Perforce `-dl`), `.ignoreAmount` (`-db`) or `.ignoreAll` (`-dw`). Line numbering
depends on the mode, because the modes that ignore line endings also end a line at
a lone CR. Always take line positions from the result (`diff.a`, `diff.b`).

### Changes within lines

```swift
let words = try TokenDiff(oldLine, newLine)  // or granularity: .words
for block in words.changes {
    let highlighted = block.b.byteRange  // in newLine
}
```

`TokenDiff` has the same shape as `Diff`, with tokens in place of lines: runs of
word characters, whitespace or punctuation. Tokens are compared byte for byte.

### Three-way merge

```swift
let merge = try Merge(base: base, a: theirs, b: mine)
for (index, block) in merge.blocks.enumerated() {
    // block.kind: .unchanged, .changedInA, .changedInB, .changedInBoth, .conflict
    // block.base, block.a, block.b: where the block lies in each input
}

let output = merge.result(resolutions: [3: .b])        // nil while a conflict is open
let marked = merge.result(markingConflicts: .diff3)    // Git-style conflict markers
let text = output?.data
let third = output?.blockRanges[2]                     // block 2's bytes in text
```

A is the incoming side (Perforce "theirs"), B the own side (Perforce "yours").
`Merge.Source` chooses the text of a block: `.base`, `.a`, `.b`, `.aThenB` or
`.bThenA`. Blocks without a resolution use `defaultSource`: the changed side
for a change on one side, B otherwise. `blockRanges` tells where each block's
text lies in the result, for example to highlight it in an editor.

`MergeStrategy` selects the Perforce merge grid: `.optimal` (default),
`.guarded`, `.diff3`, `.guardedDiff3` or `.twoWay`.

## Command line

```bash
swift run mergecli diff [-dl|-db|-dw] [--tokens] old.txt new.txt
swift run mergecli merge [-dl|-db|-dw] base.txt theirs.txt mine.txt -o result.txt
```

`merge` lists the blocks and writes the result with conflict markers. The exit
status is 0 without differences or conflicts, 1 with them, and 2 on errors.

## Behavior

These follow from the Perforce engine and differ from tools such as Git:

- Changes from both sides to adjacent lines merge without a conflict.
- Overlapping changes that share lines are split into separate conflicts
  around the common lines, which become `.changedInBoth` blocks.
- With a whitespace mode other than `.exact`, the sides of an unchanged block
  or an identical change can differ in whitespace or line endings. The result
  takes B's text, as `diffmerge.h` documents; `DiffMerge::Read()` itself
  outputs the base or A there. A resolution can pick another side.
- With `.ignoreLineEndings`, a last line without a line ending equals the same
  line ending in LF or CR, but not one ending in CRLF.

## Memory

`Diff`, `TokenDiff` and `Merge` keep the input `Data` without copying it
(only a slice of a larger `Data` is copied) and add 8 bytes per line or token
of each input. While a merge is computed, the engine needs about 40 bytes per
line of all three inputs in addition. `result` allocates the merged text once.
Inputs of 2 GiB or more are rejected with `EngineError.inputTooLarge`. How the vendored code handles allocation
failures is described in [VENDORING.md](VENDORING.md#memory).

## License

The code in this package is available under the MIT license, see
[`LICENSE`](../../LICENSE). The vendored Perforce code is distributed under the
Perforce license in
[`Sources/CMergeEngine/Vendor/Perforce/LICENSE`](Sources/CMergeEngine/Vendor/Perforce/LICENSE),
which requires binary distributions to reproduce its copyright notice, for
example in an application's acknowledgements.
