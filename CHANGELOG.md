# Changelog

All notable changes to Seamerge are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [0.3.0] - 2026-11-15

Users of 0.2.0 download 0.3.0 once by hand from [GitHub Releases](https://github.com/cykedev/seamerge/releases). Version 0.2.0 has no update check, so it cannot offer this version.

### Added

- Updates. Seamerge checks for new versions with your consent and installs one only when you choose to. It asks once, after the second start, and the question waits while a comparison or merge started by Git is in front. The answer is kept in Settings under Updates, and Seamerge ▸ Check for Updates… checks at once.
- Compare Folders (File ▸ Compare Folders…) compares two folders in one window and lists the files that differ. View ▸ Show Identical Files adds the identical files, and Filter Files (`⇧⌘F`) narrows the list by file name or folder.
- Moved blocks. A block of lines that moved to another place is recognized in a comparison and in a merge, and both ends carry an arrow, `↓` or `↑`, that points to the other end. A click on the arrow, or Go ▸ Go to Other End of Move, makes the other end the current block.

### Changed

- The tint of a changed block runs under the line numbers up to the text, so a block reads as one band. The line-number cell of the current block keeps its fill when the pane has no focus, in the color of its side.

### Fixed

- Opening or closing the find bar no longer shrinks the text of a pane, and matches below the visible part are scrolled to.
- The bars of collapsed runs end above the find bar instead of covering it.
- Typing in the find bar of the result no longer runs decision commands.

## [0.2.0] - 2026-11-15

### Added

- A Settings window (Seamerge ▸ Settings…, `⌘,`) for the font, size, line spacing and tab width of the code, and for how each new window starts: the comparison mode, syntax highlighting, line wrapping, aligned sides, invisible characters and the base. Text settings apply at once to every open window.
- Connected sides: View ▸ Align Lines (`⌥⌘A`) shows each side as continuous text and joins the sides with bands in the seams between them, in a comparison and in a merge.
- Each kind of window remembers its size and place, and a merge remembers the split above its result.
- VoiceOver rotors for the conflicts of a merge and for the changes.
- Help ▸ Keyboard Shortcuts, a window that lists the commands and their shortcuts for merges and comparisons.
- Reduce Motion: previews show as text at once.
- View ▸ Show Ignored Changes marks the places where the two files differ only in what the comparison ignores, such as the amount of whitespace.
- Lines longer than 20,000 characters are shown cut off with an ellipsis until you work in them. The text, copying and saving always use the whole line.

### Changed

- Wrap Lines and Highlight Syntax, which were remembered for all windows, are now start values in the settings. A switch in a window changes only that window.
- The zoom steps of a window run from 9 to 24 pt, the sizes that Settings offers.

### Fixed

- Panes could go empty after Wrap Lines was switched on and off again far down a long file.
- After maximizing the result, the split above it is restored when the layout is restored.
- A reloaded file is recognized anew for its language.
- The `seamerge` command opens the app again when a session meets an app that is quitting, instead of exiting without a window. It exits with status 3 and a message if the old app does not quit in time.
- Highlights in long lines are found in one pass, so that opening and editing them no longer slows down quadratically.
- The insertion point on an empty last row stays on that row.
- VoiceOver rotor items are found by their range when the table does not know them.
- The border of a file field in Compare Files, which accepts a drop, keeps a contrast of 3:1 with every accent color.

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
