# Changelog

All notable changes to Seamerge are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.9.0] - 2026-11-24

Users of 0.8.2 and earlier get this version through Seamerge ▸ Check for Updates… or the automatic check. This release keeps the work of a merge you leave, compares text from the clipboard, and describes how to use Seamerge with Mercurial, Jujutsu, Subversion and Perforce.

### Added

- A merge that you close before you finish it keeps its work on this Mac: the result, your decisions, the text you typed, the comparison mode, the encoding and line endings, and the block you were on. When the same merge opens again, even from other paths, the work comes back as one step of undo, and the subtitle says "Earlier work restored". Undo Restore Earlier Work (⌘Z) starts fresh. The work goes once the merge is saved without open conflicts and closed, or after Reset All Decisions; otherwise it expires after 30 days, and Seamerge keeps it for at most 100 merges.
- Edit ▸ Paste (⌘V) in the sheet Compare Files puts text from the clipboard on one side: into the field with the focus, or else the first empty one. Files on the clipboard act as if dropped, and formatted text becomes plain text. In the welcome window, Paste opens the sheet with the text on the left. The side is called Clipboard, shows its number of lines, and is never written to.
- The user guide describes how to set up Seamerge as the merge and diff tool of Mercurial, Jujutsu, Subversion and the Perforce command line, with the configuration and scripts checked against those tools.

### Changed

- Leave Unresolved (⌘.) no longer asks, since the work of the merge is kept.
- The sheet before closing an unsaved merge says that the work in the window is kept until you finish the merge.

### Fixed

- After Reload, when another program changed the result, a merge that Git or the command line waits for counts as unsaved until you save. Before, closing it reported the merge as saved, and Git took the other program's file as resolved.
- A tab or line break in a name given with `--label-…` shows as a space in the window title, as it already did in the header.

## [0.8.2] - 2026-11-23

Users of 0.8.1 and earlier get this version through Seamerge ▸ Check for Updates… or the automatic check.

### Fixed

- The pointer over an arrow or a bin at the seam between the panes is the arrow, as over any button. In 0.8.1 it showed the pointer for resizing the panes.

## [0.8.1] - 2026-11-23

Users of 0.8.0 and earlier get this version through Seamerge ▸ Check for Updates… or the automatic check.

### Fixed

- A click on an arrow or a bin at the seam between the panes now copies the change. In 0.8.0 the click did nothing; Copy to Right, Copy to Left and their keys worked.

## [0.8.0] - 2026-11-22

Users of 0.7.0 get this version through Seamerge ▸ Check for Updates… or the automatic check. This release lets a comparison change its files: copy a change from one side to the other, and save.

### Added

- Copy to Right (⌥⌘→) and Copy to Left (⌥⌘←) take the text of the current change into the other file; Copy All Changes to Right and Copy All Changes to Left in the Compare menu copy every change in one step. The seam between the panes shows a button for each change that can be copied, and in a pane above the result the arrow keys copy the current change. Undo names the copy and brings back the text and the current change.
- Only files that may be written take a copy: in a comparison from Git or Git-Tower the working copy, never a copy of a commit or of the index; in a comparison you chose, an ordinary file you may write. Copied lines keep the bytes of the source, including text the comparison ignores; in Exact mode they keep its line endings, in the other modes they take those of the target.
- Save (⌘S) writes every file of the window with copied changes, and Save and Close (⌘↩) writes them and closes the window. The header says "Edited", the close button shows a dot, and closing, Change Files… or quitting asks first. Seamerge writes beside the file and then replaces it, so a failure leaves the old file as it was. If another program changes the file, Seamerge asks whether to keep the copies or reload.
- A window of several files keeps the copied changes of each file while you go to another, and marks a file with unsaved changes by a dot at the end of its row.

### Changed

- The sidebar of a window of several files and of a folder comparison groups the files by folder: the files of the top folder first, then each folder once as a heading that stays in view while its files scroll. A long folder name is shortened in the middle, and its full path shows in the tooltip. The filter keeps a heading while a file below it matches.
- A modified file no longer shows a sign in the list; new, deleted, identical and unreadable files keep theirs.
- Next File and Previous File move to ⇧⌘] and ⇧⌘[, so that ⌥⌘→ and ⌥⌘← copy changes.
- Go to Next Change After Choosing in Settings also applies to Copy to Right and Copy to Left.

## [0.7.0] - 2026-11-20

Users of 0.6.0 get this version through Seamerge ▸ Check for Updates… or the automatic check. This release adds no features: it makes Seamerge steadier, leaner with memory and faster in large files.

### Changed

- A window of several files, a folder comparison and `git difftool --dir-diff` open at once. The chosen file is compared in the background; a large one shows "Comparing…" until its lines are ready, and switching to another file no longer waits for the one before.
- Scrolling does less work: the text of a pane is no longer prepared for text checking it never uses, the decision bars keep their symbols, and the gutter sets its help tags only when they change.
- Seamerge needs much less memory with long lines: a pane lets go of the layout of lines far from the view while it scrolls, not only once scrolling rests, and a file is no longer held in several copies as it opens.
- Searching for a common word in a large file no longer holds the window, and expanding a collapsed run of lines lays out only what comes into view.
- For contributors: `Scripts/check.sh` also runs the core tests under Address, Undefined Behavior and Thread Sanitizer, and fails on any warning of the Swift compiler. The code of folder comparisons and of the Git setup lives in modules of its own.

### Fixed

- Every change of the comparison mode kept a copy of the files for as long as the window stayed open, and a closed window could keep all the comparisons it had shown.
- A window of several files crashed when it came back to a file that had fewer changes by then than the one it had been left at.
- A window of two folders crashed when the file it was reading went from both folders and no file was left.
- A window of two folders could wait for a file with empty panes when the file's sides became equal on disk while it was read.
- When the file in view went from the folders, the window briefly showed and announced the first file of the list instead of the one that took its place.
- A file that changed on disk while it was read, or while the window opened, showed its old content until it changed once more; and a reloaded file of a collection showed its old content again after going to another file and back.

## [0.6.0] - 2026-11-17

Users of 0.5.0 get this version through Seamerge ▸ Check for Updates… or the automatic check. This release gives Seamerge a welcome window.

### Added

- A welcome window replaces the window Compare Files. On the deep blue of the website it offers Compare Files…, Compare Folders… and Merge Files…, and takes two files or folders dropped on it; on the right it lists the recent comparisons by day, with their kind, folder and time.
- File ▸ Merge Files… chooses three files to merge without Git.
- Seamerge brings its own accent color, the blue of the website. macOS uses it while the accent color in System Settings is Multicolor.

### Changed

- Files are chosen in sheets: Compare Files has two fields, Left and Right; Merge Files has three, A, Base and B. Compare Files… (⌘O) shows the welcome window with its sheet from anywhere.
- Two files dropped on the welcome window open at once, the older on the left, as the Finder service opens them.
- Recent comparisons keep the time they were opened; the list shows all ten that are kept.

## [0.5.0] - 2026-11-17

Users of 0.4.1 get this version through Seamerge ▸ Check for Updates… or the automatic check. This release is about speed: large files open, scroll, switch and search much faster.

### Changed

- Scrolling is smoother. The margins no longer redraw their symbols on every step, and the overview bar no longer walks all its marks.
- A comparison window opens before the comparison is ready. If the comparison takes longer than a moment, the window shows its headers right away, says "Comparing…" and fills in; small comparisons open filled as before.
- Changing the comparison mode, reloading, applying ignore rules and undoing a mode change are prepared in the background, so the window stays responsive.
- Long lines and large blocks are much faster: jumping to a change, showing all lines and switching the line arrangement take milliseconds instead of seconds, and syntax colors are applied without delay even to a single line of megabytes.
- Searching in large files no longer blocks the window, and closing the find bar is immediate.
- Blocks over 64 KiB get no word marks, like blocks that changed almost entirely.

### Fixed

- Searching could crash the app, most often right after changing the comparison mode in a large file.
- The edges of bands between panes now meet the lines of their blocks exactly instead of a pixel apart.
- Word marks and removal marks of a line that starts with a combining mark no longer reach into the line before.
- `Scripts/install.sh` built an app that quit at launch since the update framework was added.

## [0.4.1] - 2026-11-16

Users of 0.4.0 get this version through Seamerge ▸ Check for Updates… or the automatic check.

### Added

- `Examples/Logs` holds two build logs for trying the ignore rules.

### Changed

- With the base hidden, a merge compares A with B directly: wherever A and B differ, both sides are tinted, the bands run from one side to the other, and the changed words are marked against the other side. Blocks that both sides changed alike stay untinted. The marks in the margin still tell which side changed against the base.
- Bands whose ends lie far apart turn more gently, instead of bending sharply at their tip.

### Fixed

- With scroll bars always shown, the line numbers, the tint and the bands end above the horizontal scroll bar, instead of leaving a light frame around it.
- Switching between the pages of Settings resizes the window together with the page, not after it.

## [0.4.0] - 2026-11-16

Users of 0.3.0 get this version through Seamerge ▸ Check for Updates… or the automatic check.

### Added

- Find in a window. Find (`⌘F`) searches all panes, Find Next and Find Previous are `⌘G` and `⇧⌘G`, and Find and Replace (`⌥⌘F`) replaces in the result of a merge. Replace All is one undo step.
- Ignore rules. Settings ▸ Ignored Text holds the rules that a comparison leaves out. Timestamps, UUIDs and memory addresses come with the app, and Compare ▸ Use Ignore Rules applies the rules to a comparison.
- Export as Patch (File menu) and Copy as Patch (Edit menu) write the changes as a unified diff, which `git apply` takes.
- Terminal. Seamerge ▸ Install Command Line Tool… puts the `seamerge` command into `/usr/local/bin`, and Remove Command Line Tool… takes it out again.
- Finder. Compare with Seamerge in the Services menu compares two or three files, or two folders. Files and folders dropped on the Dock icon fill Compare Files.
- Single Column. View ▸ Single Column (`⌥⌘U`) shows a comparison in one column. A segment in the toolbar chooses between Aligned Lines, Connected Sides and Single Column.
- Homebrew. The app is available as a cask: `brew install --cask cykedev/tap/seamerge`.

### Changed

- View ▸ Aligned Lines (`⌥⌘A`) chooses the aligned arrangement instead of switching the alignment on and off. View ▸ Connected Sides is `⌥⇧⌘A`.
- The button `=` in the footer is gone. The toolbar segment replaces it.
- Settings has two pages, General and Ignored Text.
- `git difftool --dir-diff` and `seamerge` with two folders open the folder comparison, as File ▸ Compare Folders… does.

### Fixed

- Seamerge no longer crashes when a comparison is switched to another mode, or reloaded, after the last change removed the end of the newer file. The crash has been in Seamerge since 0.1.0.

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
