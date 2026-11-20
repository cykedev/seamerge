# Architecture

This document describes how Seamerge is built: its modules and their dependencies, the path of a file from the command line to the window, the editing model of a merge result, and the parts that depend on TextKit 2. It describes the code in this repository. Paths are relative to the repository root.

## Packages and targets

The repository has two Swift packages.

- `Packages/MergeEngine` wraps the diff and merge engine. It contains the vendored Perforce code (`Sources/CMergeEngine/Vendor/Perforce`), an adapter that replaces the Perforce interfaces it depends on (`Sources/CMergeEngine/Adapter`), a C bridge (`Sources/CMergeEngine/include`), the Swift API (`Sources/MergeEngine`) and a small command-line tool, `mergecli`. The package also has its own tests. See `Packages/MergeEngine/VENDORING.md` for the vendored files and the changes made to them.
- `Packages/SeamergeKit` holds the Swift modules of the app and of the `seamerge` command. Its module graph is declared as a table in `Packages/SeamergeKit/Package.swift`. Every module has a test target next to it.
- `App/` holds the Xcode project and the app-level code: the app (`App/Seamerge`), the `seamerge` command-line executable (`App/SeamergeTool`), code both share (`App/Shared`), the build settings (`App/Config`) and the app tests (`App/SeamergeTests`).

The packages require Swift tools 6.2 and macOS 27.0. Warnings are errors in every target except the vendored Perforce code. Both packages turn on `InternalImportsByDefault` and `MemberImportVisibility`: an import is internal unless a public or package interface needs the module, which the file marks with `public import` or `package import`, and a file imports every module whose members it uses.

## Modules

| Module | Depends on | Responsibility |
|---|---|---|
| `TextBasics` | nothing | The vocabulary of text that the other modules share: line endings (`LineEnding`, `LineEndingCounts`, `LineEndingStyle`), the table of where lines start (`LineStarts`) and the binary searches `partitioningIndex(where:)` and `lastIndex(holding:)`. |
| `TextIO` | `TextBasics` | Reading and writing text files with their encoding and line endings. |
| `MergeModel` | `MergeEngine`, `TextBasics`, `TextIO` | The model of a session, its blocks, the lines that moved, the ignore rules, the single-column layout, the result document and its editing rules. |
| `GitSupport` | nothing | Running `git`, reading the context of a merge or comparison, and writing the Git and Tower configuration. |
| `SessionIPC` | nothing | The socket between the command and the app: requests, events, the client and the server. |
| `SyntaxKit` | nothing | Language descriptions and lexers for syntax highlighting. |
| `PaneKit` | `TextBasics` | The text panes, the row grid that aligns them, the connected layout (seams, bands and the common scroll track), the decision column and the overview bar. |
| `SeamergeCLI` | `SessionIPC`, `GitSupport` | The logic of the `seamerge` command: arguments, file checks, starting the app, the exit code. |
| `SeamergeUI` | `PaneKit`, `MergeModel`, `SyntaxKit`, `GitSupport`, `TextBasics` | The session window, its toolbar and menus, the settings (`UserSettings`), the keyboard shortcut window, the welcome window with its sheets of files and the Git integration sheet. |

The arrows point one way. The user interface knows the model, and the model knows the engine. Only `PaneKit` and `SeamergeUI` import AppKit. A module that is not in the table cannot be imported, which the compiler enforces.

`PaneKit` does not depend on `MergeModel`. The panes show rows and text; the window decides what they show.

The package exports `SeamergeUI`, `MergeModel`, `SeamergeCLI`, `SessionIPC` and `GitSupport` as libraries, the modules that the app and the command link. `PaneKit`, `SyntaxKit` and `TextIO` are used only within the package, so their declarations are `package` rather than `public`. `TextBasics` makes public only the three line ending types, which appear in the interface of `MergeModel` and `SeamergeUI`; apart from the cases of `LineEnding` and `LineEndingStyle`, their members and the rest of the module are `package`.

## App

- `App/Seamerge/main.swift` starts the app.
- `AppDelegate` builds the main menu, creates the one `UserSettings` from the defaults, starts the session coordinator and shows the welcome window when the app has nothing else to do.
- `SessionCoordinator` opens one window for each session and gives it the settings. Sessions come from the socket (`SessionServer`) or from the welcome window. Every session window has its own undo manager.
- `App/SeamergeTool` is the `seamerge` executable. It calls `SeamergeCLI` and starts the app through `WorkspaceAppLauncher` when the app is not running.
- `App/Shared/HelperLaunch.swift` holds the argument `--for-session` that the command passes when it starts the app, so that the app shows no window of its own at start.

## Data flow: from Git to the window

1. Git starts `seamerge` as its mergetool or difftool. The commands Git runs are written by `GitConfiguration` (`Packages/SeamergeKit/Sources/GitSupport/GitConfiguration.swift`): `seamerge merge --from-git --base … --local … --remote … --output …` for a merge and `seamerge diff --collect --path … -- …` for a comparison. The `--collect` option asks for the collection described below.
2. `SeamergeCommand` (`Packages/SeamergeKit/Sources/SeamergeCLI/SeamergeCommand.swift`) checks the files (`FileCheck`), reads what Git is doing (`GitContext`, `DifftoolContext` in `GitSupport`), and turns the result into a `SessionRequest` (`SessionIPC/SessionRequest.swift`). The app's `GitContext+SessionRequest.swift` carries the Git values over into the window's own types, so the app and the command share only the protocol.
3. `AppLauncher` opens the app if it is not running, and brings a running app to the front. `SessionClient` connects to the socket and retries for a while, because the app may still be starting.
4. The socket is `seamerge.sock` in a `Seamerge` folder inside the user's temporary folder (`SessionIPC/SessionSocket.swift`). The path is short and does not depend on the home folder, and it is found without the environment, which Git may change.
5. `SessionServer` (in the app) accepts the request. Requests that cannot be read never reach the handler; the client gets a `rejected` event.
6. `SessionCoordinator` opens a window for the request. The session itself is built in the background (`MergeModel/Session.swift`): `EngineAdapter` is the only code that calls the engine. It translates the engine's blocks and line splits into the types of `MergeModel`, so a change of the engine interface stays in that file.
7. The window (`SeamergeUI/SessionWindowController.swift`) shows the panes from `PaneKit`, the decision column and the toolbar. Edits to the result go through `ResultDocument`.
8. When the user saves or closes the window, the window reports a `SessionEvent` back to the client. The command maps the outcome to an exit code. For a merge, Git treats exit status 0 as resolved and anything else as unresolved (`mergetool.<name>.trustExitCode`).

A comparison that Git starts for several files of one run joins them in one window, as described below. The command then waits only until the app has taken the files over.

While the app is quitting, `SessionCoordinator` rejects new sessions with `SessionRejection.quitting`. `SeamergeCLI` then waits for the old process to end (`AppLauncher.waitUntilAppQuits(within:)`) and opens the app again. If the old process does not end in time, the command exits with status 3 and prints one line.

## Editing model

A merge is one `Session` with its blocks and one `ResultDocument`.

A session holds its files as `Session.Inputs` (`MergeModel/Session+Inputs.swift`): A and B always, the base only in a merge that has one. The window holds what it shows as `ShownSession` (`SeamergeUI/ShownSession.swift`): a comparison, or a merge with its result, whose session is the session of the result, since only a merge has one.

- A **block** (`MergeModel/Block.swift`) is a region of the inputs with its lines in each input. The blocks cover every input completely and in order. A block is unchanged, changed on one side, changed identically on both sides, in conflict, or, in a comparison, different. Blocks are numbered by position.
- A **segment** (`MergeModel/Segment.swift`) is the part of the result that belongs to one block. The segments lie back to back in the order of the blocks. Each segment records how it got its text: unchanged, taken from a source, chosen by the user, edited by hand, or an open conflict.
- A **toggle** (`MergeModel/Toggle.swift`) switches the text of one or more inputs into a block. Inputs with identical text in a block share a toggle. Whitespace differences that the comparison ignores still get their own toggle, because the bytes differ. Switching on a toggle that has no text removes the block's text and switches the other toggles off.
- A **plan** (`MergeModel/EditPlan.swift`) is what the result pane has to do for an edit or a command: the replacements in the text, in order, and the changes to the segments. The result pane carries the plan out and hands it back to `ResultDocument.apply(_:replacedTexts:)`, which returns an **undo step** (`MergeModel/UndoStep.swift`). Undo and redo restore text and segments together.

`ResultDocument` (`MergeModel/ResultDocument.swift`) enforces three rules:

1. Every block has exactly one segment, which may be empty.
2. Choosing sources always works, and replaces whatever the segment holds.
3. An open conflict is resolved only by a decision, never by typing beside it. Typing in a conflict's preview first resolves it by hand (`MergeModel/ManualResolution.swift`).

The decisions themselves are commands in `SeamergeUI` (`SessionCommand.swift`). The keys for them are in `SessionCommand+Keys.swift`. The menus and the keyboard shortcut window (`ShortcutOverview.swift`) both read these tables, so the overview cannot disagree with the menus. The VoiceOver rotors for conflicts and changes are in `BlockRotors.swift`; they find blocks by their text and leave the current block where it is.

## The session window

`SessionWindowController` (`SeamergeUI/SessionWindowController.swift`) carries out the commands of a window and validates them. The parts of the window that keep state of their own are types of their own, which the controller owns:

- `DiskWatch` (`SeamergeUI/DiskWatch.swift`) watches the files of the session and the file of the result. It joins a burst of changes into one look at the files, holds back while the window saves or compares and looks afterwards, and remembers the bytes the window has seen of each file, so that it asks about them only once. The window reloads through `DiskWatchDelegate`.

## Settings

`UserSettings` (`SeamergeUI/UserSettings.swift`) is the only type that reads the defaults of the windows. It is `@Observable`, and `SettingsWindowController` edits it.

- **Text settings** (font, size, line spacing, tab width) apply to every open window at once. The settings post a notification for them, and each window redraws its panes and keeps the line at the reading line in place.
- **Start values** (comparison mode, syntax highlighting, line wrapping, aligned or connected sides, invisible characters, the base, and Go to Next Conflict After Choosing) are read when a window opens. A switch in a window's footer changes only that window; its value is not written back to the settings.
- A value outside its range, or an unknown name, reads as its default. A size or tab width outside its range is clamped to the nearest value and saved clamped.
- Window placement is kept per kind of window (merge, comparison, several files) when a window closes, including when the app quits (`SessionWindowController+Place.swift`). A window of that kind opens there, offset when another window already stands at that place. The split above the result is kept for a merge, and not when the result is maximized.

## Panes and rows

The panes (`PaneKit`) show the inputs side by side, aligned on a row grid. The grid, not TextKit, decides where row *r* lies: `PaneTextView` places each row at its display row times the row height, in every pane, so that the panes line up. Rows that wrap take the height of the most wrapped pane they line up with. A collapsed run takes one row of room, its bar.

The overview bar, the gutter marks and the decision column read the same grid. The grid applies to the aligned layout only; the connected layout below does without it.

The tint of a changed row runs under the gutter as well. `RowShading` describes the fill and the hairlines of a row, and `PaneTextView.shading(atRow:)` is the only place that decides them. `RowLayoutFragment` and `GutterView` both draw from it, so the text and the gutter cannot disagree.

Ignored differences are marked in the panes only. `IgnoredDifferences.places(in:of:)` in `MergeModel` finds the places in each differing line by comparing tokens. `PaneContent.ignoredDifferencePlaces` passes them to the panes, which fill them with `Theme.ignoredDifferenceFill`. `SessionCommand.toggleIgnoredChanges` is in the View menu only, and it is enabled while there are places.

Lines longer than 20,000 UTF-16 units are cut for display by `LongLine` (`PaneKit`) at a character boundary, followed by an ellipsis. A line is shown whole while the insertion point or a selection lies in it. The cut affects display only: the text, copying and saving use the whole line. Row widths and wrap counts use the part that is shown.

## Connected sides

The arrangement Connected Sides (`LineArrangement`, `SeamergeUI/LineArrangement.swift`) replaces the row grid of Aligned Lines with the connected layout. Each pane then shows its own lines as continuous text, and the panes are linked along one common track. The switch is in `SessionPresentation+LineAlignment.swift`.

- `RowLayout.lineText(for:)` in `MergeModel` gives the text of one side without filler rows. `ScrollMap` maps a position in one side to the matching position in another, in blocks and lines, from the starts of the blocks in both sides.
- `PaneKit/ScrollTrack.swift` is the common track, and it measures collapsed runs and wrapped lines in the heights of the panes. It consists of stretches that alternate between unchanged lines and changed blocks. Each stretch is as long on the track as in the pane that shows it highest. A pane takes each place on the track to a place of its own, moving more slowly across a stretch that it shows lower, and standing still across a stretch without rows. `ScrollSync.setTrack(for:)` installs the track in place of the row mapping. `ScrollTrack(panes:)` returns `nil` when the panes do not have the same number of blocks, and the panes then stay still rather than follow a track measured from mixed content.
- A pane that is scrolled by hand moves the track, and the other panes follow it. A pane that scrolls to a place, such as a jump or the insertion point, sets the track to that place. `ScrollSync.align(to:)` brings the panes together again after new content, collapsing or a switch.
- `PaneKit/PaneSeam.swift` draws the bands in the seam between two neighboring panes, which is 28 pt wide (`Theme.seamWidth`). A band runs between the edges of one block in both panes and fades from one tint to the other. The seam only draws: it takes no clicks, and it is hidden from VoiceOver. `SeamSplitView` in `SeamergeUI/SessionSplitViewController.swift` makes room for it and keeps the divider draggable.
- `PaneContent.marksBlocksWithoutRows` draws a hairline for a block that has no rows in one pane.
- In a merge, `SessionPresentation+LineAlignment.swift` links A, the base, B and the result on one track. Without the base, A and B share one seam. `SessionChanges.blocksWithoutDifference(between:and:)` gives the blocks that get no band, because their panes do not differ.

## TextKit 2

The text views use TextKit 2. Points that differ from a plain `NSTextView`:

- Never access `textView.layoutManager`. Reading it switches the text view back to TextKit 1 for good, and the rest of the code assumes TextKit 2.
- `PaneContentStorage` (`PaneKit/PaneContentStorage.swift`) hides the paragraphs of collapsed runs from TextKit. Without it, TextKit enumerates every hidden paragraph after each layout, which is slow in long files with runs collapsed.
- `RowLayoutFragment` (`PaneKit/RowLayoutFragment.swift`) draws each row: the full-width fill, the highlights of changed runs, the text and the marks of removed text. TextKit keeps fragments across layout changes, so the fragment asks its painter what to draw at each draw, and the pane redraws the rows after a change.
- The selection is drawn by the fragment, translucent and above the row fills, because AppKit's own selection is opaque and would hide the row tints.
- A change of row heights that leaves the text as it is, such as turning Wrap Lines on or off or a row growing beside a neighbor's wrap, must discard the paragraph elements from the first changed row on (`PaneTextView.setWrappedRows`, `PaneContentStorage.discardElements`, located by `WrappedRows.firstRow(differingFrom:)`). Invalidating the layout is not enough: TextKit keeps the frames of the fragments above, and far down a long file it then looks for the visible rows at the wrong place, and the panes show nothing.
## Moved lines

The engine reports a moved run as a removal in one place and an insertion in another, so `MergeModel` finds moves after each engine run and leaves the engine unchanged.

- `MoveDetection.swift` finds the moves of a comparison. It splits a changed block at the edges of each moved run, so that a moved run is a block of its own.
- `MoveDetection+Merge.swift` finds, for each side of a merge, the contributions to a block that moved against the base. Merge blocks are never split, because decisions attach to them.
- Equality is the engine's. `EngineAdapter.equalLines(_:_:mode:)` and `EngineAdapter.linesAreEqual(_:_:mode:)` are the only definitions of equal lines. A checksum index per comparison mode only selects candidates; the engine must find both runs equal, and an equal stretch counts only with a unique anchor line.
- A run is a move only if it occurs once on each side and has at least twenty letters and digits, counted as Unicode letters and digits. A run that occurs twice is no move.
- `Session` computes the moves when it is built, so a change of mode and a reload compute them again. `Session.moves` lists them by source block. `Session.move(endingIn:on:readingFrom:)` returns the move that ends in a block on a pane, reversed when the sides are swapped.
- `Move` has two ends (`Move.source` and `Move.destination`), each with its block, its pane role and its lines.

- PaneKit shows an end of a move as a mark in the gutter (`MoveMark`), an arrow typed in the code font that points up or down to the other end, with its help text and VoiceOver name in `MarkHelp`. A click on the mark reaches the window through the pane's delegate.
- In SeamergeUI, `SessionChanges` counts each end as a change, and the command Go to Other End of Move (`SessionCommand`) makes the other end the current block. The panes take the marks from `Session.move(endingIn:on:readingFrom:)`, so swapping the sides needs no rule of its own.

## Ignore rules

Ignore rules (`IgnoreRule.swift`) are patterns whose matches the comparison disregards. They work by masking, so the engine is not changed. `IgnoreMask` builds a masked copy of each file, line by line, and the engine compares the masked copies. `ComparedFile` keeps the real text for display and the masked text for comparison, and move detection reads only the masked text.

- `RuleMatcher` finds the matches per line with a time limit of one second per rule and file. A rule that is too slow has no effect on that file, and `Session.ignoreRuleProblems` reports why a rule had no effect.
- Lines that a rule matches entirely are removed from the edges of changed blocks and become unchanged blocks (`EntirelyMatchedLines.swift`). `IgnoredDifferences` marks the matched places for the panes.
- `Session.diff(old:new:mode:ignoring:)` takes the rules. `Session.merge` takes none, so a merge compares all text.

The window's **Use Ignore Rules** command (`SeamergeUI/SessionWindowController+IgnoreRules.swift`) passes the switched-on rules to `Session.loadDiff(old:new:mode:ignoring:)`; the same file bundles the logic that a change of the rules in Settings triggers. The rules are kept in `UserSettings.ignoreRules`, with the built-in rules first, and the built-in patterns are in `BuiltInIgnoreRule.swift`. The Ignored Text page of Settings (`IgnoredTextViewController`) edits them. `IgnoreRule.trial(on:mode:)` (`MergeModel/IgnoreRule+Trial.swift`) applies the same mask as a comparison to sample text, for the trial field; it returns the matched UTF-16 ranges or the problem with the rule.

## Single-column layout

`SingleColumnLayout` (`MergeModel/SingleColumnLayout.swift`) arranges a comparison in one column. An unchanged pair of lines appears once, with the text of the second side. A changed block shows the lines of the first side, then those of the second. The layout is derived from `Session.blocks`, and it maps rows to blocks and lines in both directions by binary search (`place(atRow:)`, `row(ofLine:in:)`).

`PaneKit` draws two line-number columns for it (`SideLineNumbers`) and the second part of a block as its own `PaneBlockPart`.

The window offers the layout as the arrangement Single Column. `LineArrangement` (`SeamergeUI/LineArrangement.swift`) names the three arrangements, Aligned Lines, Connected Sides and Single Column, with one set of titles for the toolbar segment, the View menu and Settings. `SessionSplitViewController.columnPane` shows the column with its own header, and `SessionPresentation+SingleColumn.swift` switches the arrangement while it keeps the current block and the reading line. The column maps its rows to the grid of the other arrangements with `gridRow(ofColumnRow:)` and `columnRow(ofGridRow:)`; collapsing, search, jumps and reloading all go through these mappings.

## Search across panes

The window has one find bar, the standard `NSTextFinder` bar in the container `SessionContentController` above the footer. The panes have no bar of their own. `SessionWindowController+Search` owns the commands Find, Find and Replace, Replace All, Find Next and Find Previous, and Use Selection for Find, which work regardless of which pane has the focus.

`PaneSearch` (`PaneKit`) runs one finder over several pane views. Its owner gives the sections and their order. `SessionPresentation+Search.swift` gives the sections of a window: for each stretch, the unchanged lines before a block, then the block, with the base left out while it is hidden and a maximized result searched alone. The sections are set again after each show, change of alignment, base, maximizing and file change, and only when they differ. Filler rows and previews are not searched.

The finder receives parts of at most 65,536 characters per section, not one part per line. Lines inside a part are separated by line feeds, so a match cannot reach across a line break; a match that holds one belongs to no pane, and Find Next moves to its end. `PaneSearch` keeps the matches while the finder drops them on losing focus, and drops them on a change of the text.

`SearchText` is an immutable snapshot of a pane's text, kept behind a `Mutex`. Only the main thread replaces the snapshot, as a whole, and `string(at:)` may be called on the finder's threads. Replacing goes through `PaneEditingDelegate` of the pane that is editable, and a replace-all forms one undo step named Replace All, which the controller collects from the steps of the replacement. `PaneSearch.close()` removes the find indicator and detaches the finder from the window; the window calls it when it closes and in its deinit, because the finder otherwise uses a released indicator. `OverviewBar.matchRows` marks the matches in the overview bar.

## Updates

Seamerge checks for updates with Sparkle, which only the app target links. The packages and the `seamerge` command do not import it.

- `SparkleUpdater` (`App/Seamerge/SparkleUpdater.swift`) owns the `SPUUpdater`. It uses a subclass of `SPUStandardUserDriver`, which hands a found version or the consent question to `QuestionGate`. The gate holds them while `Updater` reports that a session window is in front.
- `Updater` (`App/Seamerge/Updater.swift`) holds the rules. It starts with the app, also when Git starts the app. It shows a held question or version when a window without a session becomes key. While a `seamerge` helper waits for the app (`SessionCoordinator.isServingHelper`), it does not relaunch, and an installation waits until the app quits. Sparkle's request to quit is refused only while a helper waits.
- `SoftwareUpdater` is the part of Sparkle that `Updater` uses. Tests replace it with `SoftwareUpdaterDouble`.
- `AutomaticUpdateSetting` (`SeamergeUI`) is the setting that the settings window edits. The Updates group is the last group of its form.
- `App/Config/Info.plist` holds the feed URL, `https://www.seamerge.app/appcast.xml`, and the public key. The feed is the `appcast.xml` attached to the latest GitHub release, and the website redirects to it. Automatic installation is off.
- The build phase "Keep English Only in Sparkle" removes the translations of Sparkle. The script sandbox allows only declared paths, so its outputs are listed in `App/Config/SparkleTranslations.xcfilelist`.
- `Scripts/release.sh` builds from `git archive HEAD`, signs Sparkle from the inside out, notarizes the app, and writes the appcast with `generate_appcast`, taking the release notes from `CHANGELOG.md`.

## Git and Tower

`GitSupport` runs `git` with an argument list and never through a shell (`Git.swift`). Each command has a time limit.

`GitIntegration` (`GitSupport/GitIntegration.swift`) makes Seamerge the Git diff and merge tool. It writes only the entries of `GitConfiguration` into the global configuration, remembers the values it replaces so that removing restores them, and leaves a value that the user changed since as it is. `TowerConfiguration` (`GitSupport/TowerConfiguration.swift`) adds a launch script to Tower's compare tools folder and leaves the other entries in the list alone.

`Git.installed` (`GitSupport/Git+Installation.swift`) does not count `/usr/bin/git` as installed unless the developer directory is present.

## Collecting files and directory diffs

Git and Tower start one `difftool` call for each file of a run, and each call may open a window of its own. The app joins the calls of one run into one window with a sidebar, the collection.

- **When files are collected.** The command sends the origin of the call with `--collect` (`Packages/SeamergeKit/Sources/SeamergeCLI/SeamergeCommand.swift`). Only a run that Git numbers is collected: Git gives the count of files with `GIT_DIFF_PATH_TOTAL`, and the run is found by its process, which `ProcessRun` identifies by process ID and start time and which skips shells (`Packages/SeamergeKit/Sources/GitSupport/ProcessRun.swift`). Without a numbered run, each call opens its own window.
- **Origin and request.** The origin and the run travel with the diff request (`SessionIPC/SessionRequest.swift`, `SessionIPC/SessionRequest+Origin.swift`). A folder comparison has its own request, `SessionRequest+Folders.swift`.
- **Joining.** `App/Seamerge/SessionCoordinator.swift` lets a call join the collection of its origin, accept it, or reject it. From the second file of a run on, the command does not activate the app again.
- **Ordering and end of receiving.** `SeamergeUI/FileCollection.swift` keeps the files in the order of Git's numbers, or by path, and records when the files of the run are complete. The sidebar shows the progress while files still come.
- **Copies.** `SeamergeUI/CollectionCache.swift` copies every side that is not in the working tree, because Git and Tower delete their temporary files when the call ends. The copies go when the window closes, and a crash's leftovers go when the app next starts.
- **Sidebar.** `SeamergeUI/CollectionSplitViewController.swift` and `SeamergeUI/FileListViewController.swift` show the sidebar; View ▸ Show Sidebar (`⌃⌘S`) is in `App/Seamerge/MainMenu.swift`. Go ▸ Next File and Previous File are `SessionCommand` cases with keys in `SeamergeUI/SessionCommand+Keys.swift`.
- **Renames.** There is no renamed state. Git's difftool does not pass renames on, so a renamed file appears as a deleted file and a new file.

**Directory diff.** `git difftool --dir-diff` gives two folders, and the helper compares them in one window. `SeamergeCLI` sets `SessionRequest.Folders.isFromGit` when the command runs with `--collect` or `--path`; a missing key means the folders are not from Git. `SessionCoordinator.serveFolders` opens the window with `FileCollection(comparing:linkFolder:workingTree:)`, the same window as File ▸ Compare Folders…, and answers `.saved` when it closes. `SeamergeUI/FolderComparer.swift` pairs the files of the two folders by their path: a file only on the right is new, one only on the left is deleted. Under Git, a file of the working tree is linked by Git instead of copied, and the link is followed, so that the side is the working copy (`FolderItem.Kind.workingCopy`); `FileCollection.namingFolders` is `nil` then, and the sides take Git's names. Any other link is compared by its target and never followed. Two folders always count as a directory diff, even without `--collect`. If no file differs, the command opens no window and exits with 0.

Tower passes two folders to the launch script when its setting "Perform directory diff" is on. The script is written by `GitSupport/TowerConfiguration.swift`.

## Patches

`MergeModel/UnifiedDiff.swift` and `UnifiedDiff+File.swift` write a unified diff. Each pair of files is compared again with `EngineAdapter.diff(… mode: .exact)`, on the raw bytes and not on the decoded text, so the patch records every byte whatever the comparison mode of the window. Hunks, headers and quoting are only the formatting; there is no second diff logic. `UnifiedDiff.data(of:)` returns bytes, and `text(of:)` returns the text with each file in its detected encoding.

- `SeamergeUI/PatchContent.swift` reads, compares and writes outside the main actor (`@concurrent`). `SessionWindowController+Patch.swift` and `SessionSheets+Patch.swift` hold the commands Export as Patch and Copy as Patch, the save panel and the failure sheet. The commands are valid only where the bytes of a file pair differ.
- New and deleted files get `new file mode 100644` or `deleted file mode 100644` lines, because `git apply` rejects `/dev/null` under `diff --git` without them. The patch therefore carries no file mode, and an executable file comes out as 644.
- The patch uses the paths Git would quote. The `patch` of macOS does not read quoted paths, but `git apply` does.

## Finder service and Dock

`App/Config/Info.plist` declares the service **Compare with Seamerge** (`NSServices`, message `compareWithSeamerge`) for public data and folders, and a document type Folder with rank None, so Seamerge takes files and folders from the Dock without becoming their default app.

- `App/Seamerge/AppDelegate+Service.swift` reads the file URLs from the pasteboard and brings the app to the front. `AppDelegate` is the `servicesProvider`.
- `App/Seamerge/ServiceSelection.swift` sorts a selection into one entry, two files, two folders, three files or other. Two files open at once through `SessionCoordinator.open`, the older on the left; an error opens the sheet of the files on the welcome window with the reason. Other selections say so in the sheet Compare Files.
- `registerServiceIfInstalled()` calls `NSUpdateDynamicServices` only for an app in `/Applications` or `~/Applications`, at each start, so an update refreshes the entry.
- At launch, the welcome window appears only if neither the service nor an open event arrived in time (`hasReceivedTask`) and no session window is open (`startWindowTask`).
- Files and folders dropped on the Dock icon fill the sheet Compare Files, or Merge Files for three files, and open nothing.

## Tests

- Each module has a test target next to its sources, which may also import the modules its module depends on.
- `App/SeamergeTests` tests the app. `SystemIntegrationStore` takes the bundle, the home folder and the environment as parameters, so the tests run in a sandbox folder and do not touch the real configuration. `App/SeamergeTests/Support/AppSandbox.swift` sets that up.
- `Scripts/check.sh` runs the format check, the build and the tests of every package and of the app. It is the only check of the repository.
- The same script runs the tests of the engine and of the core modules a second time under the sanitizers: address and undefined behaviour for the engine with its bridge to C++, for TextBasics, TextIO, SyntaxKit and MergeModel and for the search of PaneKit; thread for GitSupport, SessionIPC, SeamergeCLI and the search of PaneKit. Tests that show windows are left out.
