import AppKit
import Testing

@testable import PaneKit

/// Checks that the fragments of a text far wider than the pane draw only around the part in
/// view, while what shows stays the same: the rows filled across the view and the text where the
/// user scrolls sideways.
@MainActor
@Suite struct WideTextDrawingTests {
  /// A pane of 40 lines of 2 000 characters, every fifth row in a block, in a window 600 wide.
  private static func widePane() -> (PaneView, NSWindow) {
    let pane = PaneView()
    let blocks = stride(from: 0, to: 40, by: 5).map {
      PaneBlock(rows: $0..<$0 + 1, style: .tinted(.b))
    }
    pane.content = CodeRows.content(count: 40, length: 2_000, blocks: blocks)
    let window = Rendering.host(pane, size: CGSize(width: 600, height: 300))
    return (pane, window)
  }

  /// The fragments that TextKit has laid out for the part of `textView` in view.
  private static func fragmentsInView(of textView: PaneTextView) throws -> [NSTextLayoutFragment] {
    let manager = try #require(textView.textLayoutManager)
    let viewport = try #require(manager.textViewportLayoutController.viewportRange)
    var fragments: [NSTextLayoutFragment] = []
    manager.enumerateTextLayoutFragments(from: viewport.location) { fragment in
      guard let range = fragment.textElement?.elementRange,
        range.location.compare(viewport.endLocation) == .orderedAscending
      else { return false }
      fragments.append(fragment)
      return true
    }
    return fragments
  }

  @Test func fragmentsOfLongLinesDrawAroundThePartInViewOnly() throws {
    let (pane, window) = Self.widePane()
    defer { window.close() }
    let textView = pane.textView
    let visible = textView.visibleRect
    #expect(textView.bounds.width > 10 * visible.width)
    let fragments = try Self.fragmentsInView(of: textView)
    #expect(!fragments.isEmpty)
    for fragment in fragments {
      // The part in view and as much again on either side, with the reach of the marks.
      #expect(fragment.renderingSurfaceBounds.width <= 3 * visible.width + 20)
    }
  }

  @Test func fragmentsOfAShortTextDrawAcrossTheWholeView() throws {
    let pane = PaneView()
    pane.content = CodeRows.content(count: 40, length: 80)
    let window = Rendering.host(pane, size: CGSize(width: 600, height: 300))
    defer { window.close() }
    let textView = pane.textView
    for fragment in try Self.fragmentsInView(of: textView) {
      let surface = fragment.renderingSurfaceBounds.offsetBy(
        dx: fragment.layoutFragmentFrame.minX + textView.textContainerOrigin.x, dy: 0)
      #expect(surface.minX <= 0 && surface.maxX >= textView.bounds.width)
    }
  }

  @Test func fragmentsDrawThePartInViewAfterScrollingFarSideways() throws {
    let (pane, window) = Self.widePane()
    defer { window.close() }
    let textView = pane.textView
    for x in [textView.bounds.width / 2, textView.bounds.width - textView.visibleRect.width] {
      textView.scroll(CGPoint(x: x, y: 0))
      window.contentView?.layoutSubtreeIfNeeded()
      let visible = textView.visibleRect
      let fragments = try Self.fragmentsInView(of: textView)
      #expect(!fragments.isEmpty)
      for fragment in fragments {
        let surface = fragment.renderingSurfaceBounds.offsetBy(
          dx: fragment.layoutFragmentFrame.minX + textView.textContainerOrigin.x, dy: 0)
        #expect(surface.minX <= visible.minX && surface.maxX >= visible.maxX, "at \(x)")
      }
    }
  }

  @Test func textFarToTheRightIsDrawn() throws {
    let (pane, window) = Self.widePane()
    defer { window.close() }
    let textView = pane.textView
    textView.scroll(CGPoint(x: textView.bounds.width - 2 * textView.visibleRect.width, y: 0))
    let picture = try Rendering.bitmap(of: pane)
    // Each row is a line of filler words, so ink lies on every row across the part in view.
    let inked = stride(from: 0, to: picture.pixelsWide, by: 2).count { column in
      (0..<picture.pixelsHigh).contains { row in
        (picture.colorAt(x: column, y: row)?.brightnessComponent ?? 1) < 0.5
      }
    }
    #expect(inked > picture.pixelsWide / 4)
  }
}
