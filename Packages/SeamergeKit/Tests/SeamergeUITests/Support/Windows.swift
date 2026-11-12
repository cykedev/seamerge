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
    workspace: WorkspaceRecorder = WorkspaceRecorder()
  ) throws -> SessionWindowController {
    let controller = SessionWindowController(
      session: session, context: context, undoManager: UndoManager(), displayOptions: options,
      pasteboard: .withUniqueName(), workspace: workspace)
    let window = try #require(controller.window)
    window.contentView?.layoutSubtreeIfNeeded()
    return controller
  }

  /// Every pane of the window: A, Base and B as far as they take part, then the result.
  static func panes(of controller: SessionWindowController) -> [PaneView] {
    controller.layout.sourcePanes.map(\.pane) + [controller.layout.resultPane]
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
