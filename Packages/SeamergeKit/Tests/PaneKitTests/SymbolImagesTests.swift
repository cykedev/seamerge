import AppKit
import Testing

@testable import PaneKit

/// Checks that the rows of the decision column and the gutter make the images of their signs once:
/// AppKit draws them again at every step of scrolling, and only a new theme or appearance asks for
/// new images.
@MainActor
@Suite struct SymbolImagesTests {
  @Test func drawingTheRowsAgainMakesNoImages() throws {
    let (pane, _, window, _) = DecisionColumnTests.resultPane()
    defer { window.close() }
    let rows = Self.descendants(of: pane, as: DecisionRow.self)
    let arrows = Self.descendants(of: pane, as: ResetBlockButton.self)
    let caches = rows.map(\.symbols) + arrows.map(\.symbols)
    let views: [NSView] = rows + arrows
    Self.draw(views)
    let made = caches.map(\.madeCount)
    #expect(made.contains { $0 > 0 })
    for _ in 0..<3 {
      Self.draw(views)
    }
    #expect(caches.map(\.madeCount) == made)
  }

  @Test func anotherAppearanceMakesImagesOnceForItself() throws {
    let (pane, _, window, _) = DecisionColumnTests.resultPane(
      appearance: NSAppearance(named: .aqua))
    defer { window.close() }
    let rows = Self.descendants(of: pane, as: DecisionRow.self)
    Self.draw(rows)
    let made = rows.map(\.symbols.madeCount)
    window.appearance = NSAppearance(named: .darkAqua)
    Self.draw(rows)
    let madeInDark = rows.map(\.symbols.madeCount)
    #expect(madeInDark.reduce(0, +) > made.reduce(0, +))
    window.appearance = NSAppearance(named: .aqua)
    Self.draw(rows)
    window.appearance = NSAppearance(named: .darkAqua)
    Self.draw(rows)
    #expect(rows.map(\.symbols.madeCount) == madeInDark)
  }

  @Test func aNewThemeMakesTheImagesAgain() throws {
    let (pane, _, window, _) = DecisionColumnTests.resultPane()
    defer { window.close() }
    let rows = Self.descendants(of: pane, as: DecisionRow.self)
    Self.draw(rows)
    let made = rows.map(\.symbols.madeCount)
    for row in rows {
      row.theme = Theme(
        font: .monospacedSystemFont(ofSize: 16, weight: .regular), increasesContrast: true)
    }
    Self.draw(rows)
    let madeAgain = zip(rows.map(\.symbols.madeCount), made).map { $0 - $1 }
    #expect(madeAgain == made)
  }

  /// The gutter keeps its rings by colors of the system, which are the same object each time they
  /// are asked for and resolve as the rings draw: drawing again, in another appearance or without
  /// the focus, makes no ring, and a new theme makes them again.
  @Test func drawingTheGutterAgainMakesNoRings() throws {
    let (gutter, window) = Self.gutterWithRings()
    defer { window.close() }
    Self.draw([gutter])
    // A ring in the secondary color and the ring of row 6 in the color of the filled cell.
    let rings = gutter.ringImages
    #expect(rings.count == 2)
    for _ in 0..<3 {
      Self.draw([gutter])
    }
    window.appearance = NSAppearance(named: .darkAqua)
    Self.draw([gutter])
    #expect(gutter.ringImages.count == rings.count)
    for (color, ring) in rings {
      #expect(gutter.ringImages[color] === ring)
    }
    gutter.theme = Theme(
      font: .monospacedSystemFont(ofSize: 16, weight: .regular), increasesContrast: true)
    #expect(gutter.ringImages.isEmpty)
  }

  @Test func aNewThemeOrSizeMakesTheArrowAgain() throws {
    let (pane, _, window, _) = DecisionColumnTests.resultPane()
    defer { window.close() }
    let arrow = try #require(Self.descendants(of: pane, as: ResetBlockButton.self).first)
    Self.draw([arrow])
    #expect(arrow.symbols.madeCount == 1)
    arrow.theme = Theme(
      font: .monospacedSystemFont(ofSize: 16, weight: .regular), increasesContrast: true)
    Self.draw([arrow])
    #expect(arrow.symbols.madeCount == 2)
    arrow.symbolSize += 2
    Self.draw([arrow])
    #expect(arrow.symbols.madeCount == 3)
    arrow.symbolSize += 0
    Self.draw([arrow])
    #expect(arrow.symbols.madeCount == 3)
  }

  /// The gutter of a focused pane with the rings of ignored differences at rows 2, 3 and 6, and the
  /// current block over rows 5 to 7, whose ring takes the color of the filled cell.
  private static func gutterWithRings() -> (GutterView, NSWindow) {
    let pane = PaneView(theme: Theme())
    let content = CodeRows.content(count: 40)
    pane.content = PaneContent(
      text: content.text, lineNumbers: content.lineNumbers,
      blocks: [PaneBlock(rows: 5..<8, style: .tinted(.a))], ignoredDifferenceRows: [2, 3, 6])
    pane.currentBlock = 0
    let window = Rendering.host(
      pane, size: CGSize(width: 360, height: 300), appearance: NSAppearance(named: .aqua),
      isKey: true)
    window.makeFirstResponder(pane.documentView)
    return (pane.gutterView, window)
  }

  private static func draw(_ views: [NSView]) {
    for view in views {
      guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
      view.cacheDisplay(in: view.bounds, to: bitmap)
    }
  }

  private static func descendants<View: NSView>(of view: NSView, as type: View.Type) -> [View] {
    view.subviews.flatMap { subview in
      [subview as? View].compactMap(\.self) + descendants(of: subview, as: type)
    }
  }
}
