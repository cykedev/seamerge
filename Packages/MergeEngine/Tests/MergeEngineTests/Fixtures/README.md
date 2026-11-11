# Test fixtures

Each directory is one case. Two-way cases (`diff-*`) contain `a` and `b`.
Three-way cases (`merge-*`) contain `base`, `a` (incoming side) and `b` (own
side). Some files deliberately contain CR bytes, missing final newlines, NUL
bytes or bytes that are not valid UTF-8; view them with `od -c`.

| Case | What it covers |
|---|---|
| `diff-crlf` | The same three lines with LF and with CRLF endings. |
| `diff-empty` | An empty file and a two-line file. |
| `diff-missing-final-newline` | `last` without and with a final newline. |
| `diff-nonutf8` | Latin-1 text, NUL bytes, a lone `0x80` line. |
| `diff-two-changes` | Two separate change regions, one growing by a line. |
| `diff-whitespace` | One line per whitespace rule: amount, appearance, trailing, CRLF, leading tab. |
| `merge-adjacent` | A and B change neighbouring lines. |
| `merge-clean` | Separate changes on both sides, at start, middle and end. |
| `merge-conflict` | Both sides change the same line differently. |
| `merge-crlf` | A converts to CRLF, B edits a line. |
| `merge-delete` | A deletes lines, B edits elsewhere. |
| `merge-delete-vs-edit` | A deletes a line that B edits. |
| `merge-empty-all` | Three empty files. |
| `merge-empty-base` | Empty base, only A adds text. |
| `merge-empty-both-add` | Empty base, A and B add different text. |
| `merge-insert-same-place` | A and B insert different lines at the same position. |
| `merge-missing-final-newline` | A adds a final newline and a line, B edits the first line. |
| `merge-missing-final-newline-conflict` | Both sides change a last line that has no newline. |
| `merge-nonutf8` | Non-UTF-8 bytes changed on both sides. |
| `merge-same-change` | A and B make the identical change; B also appends a line. |
| `merge-split-conflict` | Overlapping changes that share a common line. |
| `merge-whitespace-edit` | A only re-indents, B edits a different line. |
| `merge-whitespace-vs-edit` | A changes whitespace, B changes text, in the same line. |
