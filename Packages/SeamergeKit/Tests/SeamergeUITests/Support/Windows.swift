import AppKit
import FolderCompare
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Opens session windows for the tests, laid out at their standard size without a screen.
@MainActor
enum Windows {
  /// The controller of a window for `session`, laid out, with movement reduced unless
  /// `options` say otherwise, so that every jump lands at once; for an `unavailable`
  /// comparison, `session` is its empty session; for a `pendingComparison`, `session` names
  /// the files without their lines.
  ///
  /// Windows that share `syntaxChoices` find the languages chosen in each other.
  static func controller(
    for session: Session, context: SessionContext = SessionContext(),
    options: DisplayOptions = DisplayOptions(reducesMotion: true),
    workspace: WorkspaceRecorder = WorkspaceRecorder(), prompts: PromptRecorder = PromptRecorder(),
    undoManager: UndoManager = UndoManager(), unavailable: UnavailableComparison? = nil,
    settings: UserSettings = .private(), syntaxChoices: SyntaxChoices = SyntaxChoices(),
    pendingComparison: PendingComparison? = nil
  ) throws -> SessionWindowController {
    WindowAnimations.turnOff()
    TransparentWindows.turnOn()
    let controller = SessionWindowController(
      session: session, context: context, undoManager: undoManager, displayOptions: options,
      pasteboard: .withUniqueName(), workspace: workspace, prompts: prompts, doneStyle: .standard,
      settings: settings, syntaxChoices: syntaxChoices, window: SessionWindow(),
      unavailable: unavailable, pendingComparison: pendingComparison)
    let window = try #require(controller.window)
    window.contentView?.layoutSubtreeIfNeeded()
    return controller
  }

  /// Draws the window of `session` at `size`, or at its least size for `nil`, after `prepare`;
  /// for a `pendingComparison`, the window that waits for it.
  ///
  /// With `actsAsKey`, the window acts as the key
  /// window, so that the focus shows in the accent color.
  static func picture(
    _ session: Session, context: SessionContext, look: Look,
    options: DisplayOptions = DisplayOptions(), doneStyle: SessionToolbar.DoneStyle = .standard,
    settings: UserSettings = .private(), actsAsKey: Bool = false,
    size: CGSize? = WindowMetrics.defaultContentSize, named name: String,
    unavailable: UnavailableComparison? = nil, pendingComparison: PendingComparison? = nil,
    prepare: (SessionWindowController) -> Void = { _ in }
  ) throws {
    let controller = SessionWindowController(
      session: session, context: context, undoManager: UndoManager(), displayOptions: options,
      pasteboard: .withUniqueName(), workspace: WorkspaceRecorder(), prompts: PromptRecorder(),
      doneStyle: doneStyle, settings: settings,
      window: actsAsKey ? KeySessionWindow() : SessionWindow(), unavailable: unavailable,
      pendingComparison: pendingComparison)
    let window = try #require(controller.window)
    defer { window.close() }
    Rendering.prepare(window, size: size ?? window.contentMinSize, appearance: look.appearance)
    controller.layout.placeDividers()
    controller.stateDidChange()
    prepare(controller)
    try Rendering.write(Rendering.bitmap(of: window), named: name)
  }

  /// Every pane of the window: A, Base and B as far as they take part, then the result, if
  /// there is one.
  static func panes(of controller: SessionWindowController) -> [PaneView] {
    controller.layout.sourcePanes.map(\.pane) + [controller.layout.resultPane].compactMap(\.self)
  }

  /// The point in `pane` at the middle of the first row of `block`, a little into the text.
  static func point(inBlock block: Int, of pane: PaneView) -> CGPoint {
    let rows = pane.content.blocks[block].rows
    let row = rows.lowerBound
    let y = pane.verticalSpan(ofRows: row..<row + 1).lowerBound + pane.theme.rowHeight / 2
    return pane.convert(CGPoint(x: 8, y: y), from: pane.documentView)
  }

  /// The top of the visible part of the text of `pane`.
  static func scrollOffset(of pane: PaneView) -> CGFloat {
    pane.documentView.visibleRect.minY
  }
}

extension UserSettings {
  /// Settings in user defaults of their own, which no other test and no setting of the user
  /// sees.
  static func `private`() -> UserSettings {
    UserSettings(defaults: .privateSuite())
  }
}

extension UserDefaults {
  /// User defaults of their own named `name`, which no other test and no setting of the user
  /// sees; a test that writes to them removes them with `removePersistentDomain(forName:)`.
  static func privateSuite(
    named name: String = "SeamergeUITests.\(UUID().uuidString)"
  ) -> UserDefaults {
    guard let defaults = UserDefaults(suiteName: name) else {
      preconditionFailure("The user defaults named \(name) cannot be made")
    }
    return defaults
  }
}

/// A workspace that records what the window asks of it instead of opening anything.
@MainActor
final class WorkspaceRecorder: Workspace {
  private(set) var openedURLs: [URL] = []
  private(set) var revealedURLs: [URL] = []

  func open(_ url: URL) -> Bool {
    openedURLs.append(url)
    return true
  }

  func activateFileViewerSelecting(_ fileURLs: [URL]) {
    revealedURLs += fileURLs
  }
}

/// Prompts that answer as told and record what the window asked.
@MainActor
final class PromptRecorder: SessionPrompts {
  /// Whether to switch when asked about discarded decisions.
  var switchesAnyway = false

  /// Whether to reset when asked about discarded handwriting.
  var resetsAnyway = false

  private(set) var discardedCounts: [Int] = []
  private(set) var discardedHandwritingCounts: [Int] = []
  private(set) var failureCount = 0

  /// What happens while the window asks whether to switch although decisions would be lost.
  var whileAskingToDiscard: @MainActor () async -> Void = {}

  func confirmDiscarding(_ count: Int, in window: NSWindow) async -> Bool {
    discardedCounts.append(count)
    await whileAskingToDiscard()
    return switchesAnyway
  }

  func confirmResettingAll(discardingHandwritingIn count: Int, in window: NSWindow) async -> Bool {
    discardedHandwritingCounts.append(count)
    return resetsAnyway
  }

  func reportFailedComparison(in window: NSWindow) async {
    failureCount += 1
  }

  /// The answer to the sheet before saving with open conflicts.
  var openConflictsChoice = OpenConflictsChoice.cancel

  /// The answer to the sheet before closing with unsaved changes.
  var unsavedChangesChoice = UnsavedChangesChoice.cancel

  /// Whether to leave a merge unresolved although decisions would be lost.
  var leavesUnresolvedAnyway = false

  /// Whether to save in UTF-8 when the encoding cannot hold the result.
  var savesAsUTF8 = false

  /// Where to save when asked, or `nil` to cancel.
  var destination: URL?

  /// Whether to reload a result file that another app changed.
  var reloadsChangedResult = false

  /// Whether to reload changed files although decisions would be lost.
  var reloadsAnyway = false

  /// What the window asked, in order, in short words.
  private(set) var questions: [String] = []

  /// What happens while the window asks whether to save with open conflicts.
  var whileAskingToSaveWithOpenConflicts: @MainActor () async -> Void = {}

  func confirmSavingWithOpenConflicts(
    _ count: Int, gitTakesItAsResolved: Bool, in window: NSWindow
  ) async -> OpenConflictsChoice {
    questions.append("save with \(count) open conflicts\(gitTakesItAsResolved ? ", Git" : "")")
    await whileAskingToSaveWithOpenConflicts()
    return openConflictsChoice
  }

  func confirmClosing(
    _ name: String, openConflictCount: Int, caller: WaitingCaller?, in window: NSWindow
  ) async -> UnsavedChangesChoice {
    let callerName =
      switch caller {
      case .git: ", Git"
      case .commandLine: ", command line"
      case nil: ""
      }
    questions.append("close \(name), \(openConflictCount) open\(callerName)")
    return unsavedChangesChoice
  }

  func confirmLeavingUnresolved(
    _ name: String, discarding count: Int, gitPutsBackTheFile: Bool, in window: NSWindow
  ) async -> Bool {
    questions.append(
      "leave \(name) unresolved, \(count) decisions\(gitPutsBackTheFile ? ", Git" : "")")
    return leavesUnresolvedAnyway
  }

  /// What happens while the window offers UTF-8.
  var whileOfferingUTF8: @MainActor () async -> Void = {}

  func offerUTF8(saving name: String, in encoding: FileEncoding, in window: NSWindow) async -> Bool
  {
    questions.append("save \(name) as UTF-8 instead of \(encoding.name)")
    await whileOfferingUTF8()
    return savesAsUTF8
  }

  func reportFailedSaving(_ name: String, reason: String, in window: NSWindow) async {
    questions.append("failed saving \(name)")
  }

  /// What happens while the window asks where to save, such as a change on disk.
  var whileAskingWhereToSave: @MainActor () async -> Void = {}

  func chooseDestination(suggesting name: String, in window: NSWindow) async -> URL? {
    questions.append("where to save \(name)")
    await whileAskingWhereToSave()
    return destination
  }

  /// What happens while the window asks whether to reload a file that another app changed.
  var whileAskingToReloadChangedFile: @MainActor () async -> Void = {}

  func confirmReloadingChangedFile(_ name: String, in window: NSWindow) async -> Bool {
    questions.append("reload changed \(name)")
    await whileAskingToReloadChangedFile()
    return reloadsChangedResult
  }

  /// What happens while the window asks whether to save copied changes.
  var whileAskingToSaveChanges: @MainActor () async -> Void = {}

  func confirmSavingChanges(to names: [String], in window: NSWindow) async -> UnsavedChangesChoice {
    questions.append("save changes to \(names.joined(separator: ", "))")
    await whileAskingToSaveChanges()
    return unsavedChangesChoice
  }

  /// What happens while the window asks whether to reload although decisions would be lost.
  var whileAskingToReload: @MainActor () async -> Void = {}

  func confirmReloading(_ name: String?, discarding count: Int, in window: NSWindow) async -> Bool {
    questions.append("reload \(name ?? "files"), \(count) decisions")
    await whileAskingToReload()
    return reloadsAnyway
  }

  /// Whether to change the files although decisions would be lost.
  var changesAnyway = false

  func confirmChangingFiles(discarding count: Int, in window: NSWindow) async -> Bool {
    questions.append("change files, \(count) decisions")
    return changesAnyway
  }

  /// The answers to the sheet of a binary file, one per question: a side, or `nil` to leave the
  /// file unresolved.
  var binaryChoices: [Role?] = []

  func chooseSide(ofBinaryFile name: String, a: String, b: String, in window: NSWindow) async
    -> Role?
  {
    questions.append("binary \(name): use \(b) or \(a)")
    return binaryChoices.isEmpty ? nil : binaryChoices.removeFirst()
  }

  /// Where to export a patch, or `nil` to cancel.
  var patchDestination: URL?

  /// The number of files that each choice of the place of a patch named, `nil` for one file.
  private(set) var patchFileCounts: [Int?] = []

  func choosePatchDestination(
    suggesting name: String, fileCount: Int?, in window: NSWindow
  ) async -> URL? {
    questions.append("where to export \(name)")
    patchFileCounts.append(fileCount)
    return patchDestination
  }

  func reportFailedPatch(_ error: PatchError, exporting name: String?, in window: NSWindow) async {
    questions.append("failed patch \(name ?? "copy"): \(error.localizedDescription)")
  }
}

extension SessionWindowController {
  /// The result pane of a merge window.
  var mergeResult: PaneView {
    get throws { try #require(layout.resultPane, "A merge window has a result pane") }
  }
}

extension SessionPresentation {
  /// The result of a merge as it stands.
  var mergeResult: ResultState {
    get throws { try #require(result, "A merge has a result") }
  }

  /// The overview bar beside the result of a merge.
  var mergeResultOverviewBar: OverviewBar {
    get throws { try #require(resultOverviewBar, "A merge has a result") }
  }

  /// The decision column beside the result of a merge.
  var mergeDecisionColumn: DecisionColumnView {
    get throws { try #require(decisionColumn, "A merge has a result") }
  }
}

extension Windows {
  /// A window for `collection`, laid out without a screen, that asks `prompts`; with
  /// `fillsFirstFile`, once it shows its first file, otherwise while it may wait for it.
  static func controller(
    for collection: FileCollection, options: DisplayOptions = DisplayOptions(reducesMotion: true),
    settings: UserSettings = .private(), window: SessionWindow = SessionWindow(),
    prompts: PromptRecorder = PromptRecorder(), fillsFirstFile: Bool = true
  ) async throws -> SessionWindowController {
    WindowAnimations.turnOff()
    TransparentWindows.turnOn()
    let opening = try await SessionWindowController.opening(collection, settings: settings)
    let controller = SessionWindowController(
      session: opening.session, context: opening.context, undoManager: UndoManager(),
      displayOptions: options, pasteboard: .withUniqueName(), workspace: WorkspaceRecorder(),
      prompts: prompts, doneStyle: .standard, settings: settings, window: window,
      collection: collection, pendingFile: opening.comparison)
    if fillsFirstFile {
      await controller.phase.filling?.value
    }
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    return controller
  }

  /// Draws the window of `collection` in `look` at `size`, after `prepare`.
  static func picture(
    _ collection: FileCollection, look: Look, options: DisplayOptions = DisplayOptions(),
    settings: UserSettings = .private(), size: CGSize? = WindowMetrics.defaultContentSize,
    named name: String,
    prepare: @MainActor (SessionWindowController) async throws -> Void = { _ in }
  ) async throws {
    let controller = try await controller(for: collection, options: options, settings: settings)
    let window = try #require(controller.window)
    defer { window.close() }
    Rendering.prepare(window, size: size ?? window.contentMinSize, appearance: look.appearance)
    controller.layout.placeDividers()
    controller.stateDidChange()
    try await prepare(controller)
    window.contentView?.layoutSubtreeIfNeeded()
    try Rendering.write(Rendering.bitmap(of: window), named: name)
  }
}
