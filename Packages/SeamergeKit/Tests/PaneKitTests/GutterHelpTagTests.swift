import AppKit
import Testing

@testable import PaneKit

/// Checks that the gutter gives the help tags of its marks new areas only where they changed:
/// each change has the window find its areas under the pointer anew.
@MainActor
@Suite struct GutterHelpTagTests {
  @Test func helpTagsKeepTheirAreasUntilTheMarksMove() throws {
    let (pane, window) = Self.pane()
    defer { window.close() }
    let gutter = pane.gutterView
    let changes = gutter.toolTipAreaChanges
    #expect(changes > 0)

    // What the pane hands the gutter again, unchanged, as it does after many changes.
    let (theme, content, displayRows) = (gutter.theme, gutter.content, gutter.displayRows)
    gutter.theme = theme
    gutter.content = content
    gutter.displayRows = displayRows
    gutter.setFrameSize(gutter.frame.size)
    pane.scroll(to: .zero)
    pane.display()

    #expect(gutter.toolTipAreaChanges == changes)
  }

  @Test func scrollingGivesTheHelpTagsNewAreasOnceItRests() throws {
    let (pane, window) = Self.pane()
    defer { window.close() }
    let gutter = pane.gutterView
    let changes = gutter.toolTipAreaChanges
    let rowHeight = pane.theme.rowHeight

    // Three rows a step, to 93 rows down: the blocks, ten rows apart, stand elsewhere in view.
    for step in 1...31 {
      pane.scroll(to: CGPoint(x: 0, y: CGFloat(step) * 3 * rowHeight))
      window.contentView?.layoutSubtreeIfNeeded()
      pane.display()
    }
    #expect(pane.textView.isScrolling)
    #expect(gutter.toolTipAreaChanges == changes)

    pane.textView.scrollRestTimer?.fire()

    #expect(!pane.textView.isScrolling)
    #expect(gutter.toolTipAreaChanges == changes + 1)
  }

  /// A pane of rows with a changed block every ten rows, each with a mark in the gutter.
  private static func pane() -> (PaneView, NSWindow) {
    let blocks = stride(from: 5, to: 2_000, by: 10).map { row in
      PaneBlock(rows: row..<row + 2, style: .tinted(.a), marker: .changed)
    }
    let pane = PaneView()
    pane.content = CodeRows.content(count: 2_000, length: 40, blocks: blocks)
    let window = Rendering.host(pane, size: CGSize(width: 600, height: 400))
    window.contentView?.layoutSubtreeIfNeeded()
    pane.textView.scrollRestTimer?.fire()
    return (pane, window)
  }
}
