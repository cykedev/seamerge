# Changelog

All notable changes to Seamerge are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-11-14

First release. Requires macOS 27.0 or later.

### Added

- Three-way merge of files with their common base, with four panes: the two sources, the base and the result. Changes are shown row by row, aligned across the panes.
- Two-way comparison of files, also of two commits and of a file in the working tree against its copy.
- Decisions per block: take the text of one or both sources, the base, or nothing, with single-key commands, a decision column and context menus. Conflicts are resolved only by a decision or by editing the result by hand.
- The result is editable. Undo and redo cover text and decisions together. Changes on disk while a session is open are reloaded, and decisions are kept.
- Saving with the file's encoding and line endings kept, or with a chosen encoding and line-ending style. A merge that is not finished can be left unresolved, and Git then keeps the conflict.
- Navigation between conflicts and changes, an overview bar, scrolling kept in step across the panes, and a collapsed view of long unchanged runs.
- Comparison modes: exact, ignoring line endings, ignoring the amount of whitespace, and ignoring all whitespace. Lines whose differences the comparison ignores are marked. Merge strategies: optimal, guarded, diff3 and guarded diff3.
- Syntax highlighting for the most common languages, which can be switched off, and the language can be chosen in the footer.
- Line wrapping, invisible characters on request, a footer with the options, and a maximized result pane.
- Git integration: `seamerge` runs as `git mergetool` and `git difftool`. Git's side names and its conflict labels are shown in the window.
- Tower integration: Tower can open its diffs and merges in Seamerge once the integration is set up from the app.
- Setting up and removing the Git and Tower integration from the app. Removing restores the previous configuration.
- The `seamerge` command, with `--version`, for merges and comparisons from the terminal.
- Several files of one run, from Git or Tower, open in one window with a sidebar that lists them. `git difftool --dir-diff` compares two folders in one window.
- Accessibility: state changes are announced to assistive technology, and the panes and controls have labels.
