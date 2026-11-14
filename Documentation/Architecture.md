# Architecture

This document describes how Seamerge is built: its modules and their dependencies, the path of a file from the command line to the window, the editing model of a merge result, and the parts that depend on TextKit 2. It describes the code in this repository. Paths are relative to the repository root.

## Packages and targets

The repository has two Swift packages.

- `Packages/MergeEngine` wraps the diff and merge engine. It contains the vendored Perforce code (`Sources/CMergeEngine/Vendor/Perforce`), an adapter that replaces the Perforce interfaces it depends on (`Sources/CMergeEngine/Adapter`), a C bridge (`Sources/CMergeEngine/include`), the Swift API (`Sources/MergeEngine`) and a small command-line tool, `mergecli`. The package also has its own tests. See `Packages/MergeEngine/VENDORING.md` for the vendored files and the changes made to them.
- `Packages/SeamergeKit` holds the Swift modules of the app and of the `seamerge` command. Its module graph is declared as a table in `Packages/SeamergeKit/Package.swift`. Every module has a test target next to it.
- `App/` holds the Xcode project and the app-level code: the app (`App/Seamerge`), the `seamerge` command-line executable (`App/SeamergeTool`), code both share (`App/Shared`), the build settings (`App/Config`) and the app tests (`App/SeamergeTests`).

The packages require Swift tools 6.2 and macOS 27.0. Warnings are errors in every target except the vendored Perforce code.

## Modules

| Module | Depends on | Responsibility |
|---|---|---|
| `TextIO` | nothing | Reading and writing text files with their encoding and line endings. |
| `MergeModel` | `MergeEngine`, `TextIO` | The model of a session, its blocks, the result document and its editing rules. |
| `GitSupport` | nothing | Running `git`, reading the context of a merge or comparison, and writing the Git and Tower configuration. |
| `SessionIPC` | nothing | The socket between the command and the app: requests, events, the client and the server. |
| `SyntaxKit` | nothing | Language descriptions and lexers for syntax highlighting. |
| `PaneKit` | nothing | The text panes, the row grid that aligns them, the decision column and the overview bar. |
| `SeamergeCLI` | `SessionIPC`, `GitSupport` | The logic of the `seamerge` command: arguments, file checks, starting the app, the exit code. |
| `SeamergeUI` | `PaneKit`, `MergeModel`, `SyntaxKit`, `GitSupport` | The session window, its toolbar and menus, the Compare Files window and the Git integration sheet. |

The arrows point one way. The user interface knows the model, and the model knows the engine. Only `PaneKit` and `SeamergeUI` import AppKit. A module that is not in the table cannot be imported, which the compiler enforces.

`PaneKit` does not depend on `MergeModel`. The panes show rows and text; the window decides what they show.

## App

- `App/Seamerge/main.swift` starts the app.
- `AppDelegate` builds the main menu, starts the session coordinator and shows the Compare Files window when the app has nothing else to do.
- `SessionCoordinator` opens one window for each session. Sessions come from the socket (`SessionServer`) or from the Compare Files window. Every session window has its own undo manager.
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

## Editing model

A merge is one `Session` with its blocks and one `ResultDocument`.

- A **block** (`MergeModel/Block.swift`) is a region of the inputs with its lines in each input. The blocks cover every input completely and in order. A block is unchanged, changed on one side, changed identically on both sides, in conflict, or, in a comparison, different. Blocks are numbered by position.
- A **segment** (`MergeModel/Segment.swift`) is the part of the result that belongs to one block. The segments lie back to back in the order of the blocks. Each segment records how it got its text: unchanged, taken from a source, chosen by the user, edited by hand, or an open conflict.
- A **toggle** (`MergeModel/Toggle.swift`) switches the text of one or more inputs into a block. Inputs with identical text in a block share a toggle. Whitespace differences that the comparison ignores still get their own toggle, because the bytes differ. Switching on a toggle that has no text removes the block's text and switches the other toggles off.
- A **plan** (`MergeModel/EditPlan.swift`) is what the result pane has to do for an edit or a command: the replacements in the text, in order, and the changes to the segments. The result pane carries the plan out and hands it back to `ResultDocument.apply(_:replacedTexts:)`, which returns an **undo step** (`MergeModel/UndoStep.swift`). Undo and redo restore text and segments together.

`ResultDocument` (`MergeModel/ResultDocument.swift`) enforces three rules:

1. Every block has exactly one segment, which may be empty.
2. Choosing sources always works, and replaces whatever the segment holds.
3. An open conflict is resolved only by a decision, never by typing beside it. Typing in a conflict's preview first resolves it by hand (`MergeModel/ManualResolution.swift`).

The decisions themselves are commands in `SeamergeUI` (`SessionCommand.swift`). The keys for them are in `SessionCommand+Keys.swift`.

## Panes and rows

The panes (`PaneKit`) show the inputs side by side, aligned on a row grid. The grid, not TextKit, decides where row *r* lies: `PaneTextView` places each row at its display row times the row height, in every pane, so that the panes line up. Rows that wrap take the height of the most wrapped pane they line up with. A collapsed run takes one row of room, its bar.

The overview bar, the gutter marks and the decision column read the same grid.

## TextKit 2

The text views use TextKit 2. Points that differ from a plain `NSTextView`:

- Never access `textView.layoutManager`. Reading it switches the text view back to TextKit 1 for good, and the rest of the code assumes TextKit 2.
- `PaneContentStorage` (`PaneKit/PaneContentStorage.swift`) hides the paragraphs of collapsed runs from TextKit. Without it, TextKit enumerates every hidden paragraph after each layout, which is slow in long files with runs collapsed.
- `RowLayoutFragment` (`PaneKit/RowLayoutFragment.swift`) draws each row: the full-width fill, the highlights of changed runs, the text and the marks of removed text. TextKit keeps fragments across layout changes, so the fragment asks its painter what to draw at each draw, and the pane redraws the rows after a change.
- The selection is drawn by the fragment, translucent and above the row fills, because AppKit's own selection is opaque and would hide the row tints.

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
- **Sidebar.** `SeamergeUI/CollectionSplitViewController.swift` and `SeamergeUI/FileListViewController.swift` show the sidebar; View > Show Sidebar (`⌃⌘S`) is in `App/Seamerge/MainMenu.swift`. Go > Next File and Previous File are `SessionCommand` cases with keys in `SeamergeUI/SessionCommand+Keys.swift`.
- **Renames.** There is no renamed state. Git's difftool does not pass renames on, so a renamed file appears as a deleted file and a new file.

**Directory diff.** `git difftool --dir-diff` gives two folders, and the helper compares them in one window. `SeamergeUI/FolderComparison.swift` pairs the files of the two folders by their path: a file only on the right is new, one only on the left is deleted. A file of the working tree is linked by Git instead of copied, and the link is followed, so that the side is the working copy. Any other link is compared by its target and never followed. Two folders always count as a directory diff, even without `--collect`. If no file differs, the command opens no window and exits with 0.

Tower passes two folders to the launch script when its setting "Perform directory diff" is on. The script is written by `GitSupport/TowerConfiguration.swift`.

## Tests

- Each module has a test target next to its sources.
- `App/SeamergeTests` tests the app. `SystemIntegrationStore` takes the bundle, the home folder and the environment as parameters, so the tests run in a sandbox folder and do not touch the real configuration. `App/SeamergeTests/Support/AppSandbox.swift` sets that up.
- `Scripts/check.sh` runs the format check, the build and the tests of every package and of the app. It is the only check of the repository.
