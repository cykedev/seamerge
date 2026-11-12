import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Opens session windows for the tests, laid out at their standard size without a screen.
@MainActor
enum Windows {
  /// The controller of a window for `session`, laid out, with movement reduced unless
  /// `options` say otherwise, so that every jump lands at once.
  static func controller(
    for session: Session, context: SessionContext = SessionContext(),
    options: DisplayOptions = DisplayOptions(reducesMotion: true),
    workspace: WorkspaceRecorder = WorkspaceRecorder(), prompts: PromptRecorder = PromptRecorder(),
    undoManager: UndoManager = UndoManager()
  ) throws -> SessionWindowController {
    let controller = SessionWindowController(
      session: session, context: context, undoManager: undoManager, displayOptions: options,
      pasteboard: .withUniqueName(), workspace: workspace, prompts: prompts, doneStyle: .standard,
      window: SessionWindow())
    let window = try #require(controller.window)
    window.contentView?.layoutSubtreeIfNeeded()
    return controller
  }

  /// Draws the window of `session` at `size`, or at its least size for `nil`, after `prepare`.
  ///
  /// A responder that saves and closes stands in for the one that comes with saving, so that
  /// the button shows as it does in the app. With `actsAsKey`, the window acts as the key
  /// window, so that the focus shows in the accent color.
  static func picture(
    _ session: Session, context: SessionContext, look: Look,
    options: DisplayOptions = DisplayOptions(), doneStyle: SessionToolbar.DoneStyle = .standard,
    actsAsKey: Bool = false, size: CGSize? = WindowMetrics.defaultContentSize, named name: String,
    prepare: (SessionWindowController) -> Void = { _ in }
  ) throws {
    let controller = SessionWindowController(
      session: session, context: context, undoManager: UndoManager(), displayOptions: options,
      pasteboard: .withUniqueName(), workspace: WorkspaceRecorder(), prompts: PromptRecorder(),
      doneStyle: doneStyle,
      window: actsAsKey ? KeySessionWindow() : SessionWindow())
    let window = try #require(controller.window)
    defer { window.close() }
    let saver = SaveAndCloseStandIn()
    controller.nextResponder = saver
    Rendering.prepare(window, size: size ?? window.contentMinSize, appearance: look.appearance)
    controller.layout.placeDividers()
    controller.stateDidChange()
    prepare(controller)
    try Rendering.write(Rendering.bitmap(of: window), named: name)
    // The window does not retain its next responder.
    withExtendedLifetime(saver) {}
  }

  /// Every pane of the window: A, Base and B as far as they take part, then the result, if
  /// there is one.
  static func panes(of controller: SessionWindowController) -> [PaneView] {
    controller.layout.sourcePanes.map(\.pane) + [controller.layout.resultPane].compactMap(\.self)
  }

  /// The point in `pane` at the middle of the first row of `block`, a little into the text.
  static func point(inBlock block: Int, of pane: PaneView) -> CGPoint {
    let rows = pane.content.blocks[block].rows
    let y = (CGFloat(pane.displayRow(ofRow: rows.lowerBound)) + 0.5) * pane.theme.rowHeight
    return pane.convert(CGPoint(x: 8, y: y), from: pane.documentView)
  }

  /// The top of the visible part of the text of `pane`.
  static func scrollOffset(of pane: PaneView) -> CGFloat {
    pane.documentView.visibleRect.minY
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
final class PromptRecorder: ComparisonPrompts {
  /// Whether to switch when asked about discarded decisions.
  var switchesAnyway = false

  private(set) var discardedCounts: [Int] = []
  private(set) var failureCount = 0

  func confirmDiscarding(_ count: Int, in window: NSWindow) async -> Bool {
    discardedCounts.append(count)
    return switchesAnyway
  }

  func reportFailedComparison(in window: NSWindow) async {
    failureCount += 1
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
