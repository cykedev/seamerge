# Test fixtures

Each directory is one case. Two-way cases (`diff-*`) contain `a` and `b`.
Some files deliberately contain CR bytes, missing final newlines, NUL
bytes or bytes that are not valid UTF-8; view them with `od -c`.

| Case | What it covers |
|---|---|
| `diff-crlf` | The same three lines with LF and with CRLF endings. |
| `diff-empty` | An empty file and a two-line file. |
| `diff-missing-final-newline` | `last` without and with a final newline. |
| `diff-nonutf8` | Latin-1 text, NUL bytes, a lone `0x80` line. |
| `diff-two-changes` | Two separate change regions, one growing by a line. |
| `diff-whitespace` | One line per whitespace rule: amount, appearance, trailing, CRLF, leading tab. |
