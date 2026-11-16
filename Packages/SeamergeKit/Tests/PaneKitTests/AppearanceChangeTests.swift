import AppKit
import PaneKit
import Testing

/// Checks that a pane drawn once and then shown in another appearance or with another theme looks
/// as if it had been made that way, the symbols it keeps from drawing to drawing included.
@MainActor
@Suite struct AppearanceChangeTests {
  @Test func ringsAndBarsTakeTheColorsOfANewAppearance() throws {
    let light = try #require(NSAppearance(named: .aqua))
    let dark = try #require(NSAppearance(named: .darkAqua))
    let (changed, changedWindow) = Self.pane(theme: Theme(), appearance: light)
    defer { changedWindow.close() }
    _ = try Rendering.bitmap(of: changed)
    changedWindow.appearance = dark
    let (fresh, freshWindow) = Self.pane(theme: Theme(), appearance: dark)
    defer { freshWindow.close() }
    try Self.expectSame(changed, fresh)
  }

  /// A larger font gives the rings another size, a theme with more contrast the marks other
  /// colors.
  @Test(arguments: ThemeChange.allCases)
  func ringsAndBarsFollowANewTheme(change: ThemeChange) throws {
    let theme = change.theme
    let light = try #require(NSAppearance(named: .aqua))
    let (changed, changedWindow) = Self.pane(theme: Theme(), appearance: light)
    defer { changedWindow.close() }
    _ = try Rendering.bitmap(of: changed)
    changed.theme = theme
    let (fresh, freshWindow) = Self.pane(theme: theme, appearance: light)
    defer { freshWindow.close() }
    try Self.expectSame(changed, fresh)
  }

  /// A theme that a pane made with the standard theme is given.
  enum ThemeChange: CaseIterable, Sendable {
    case largerFont
    case moreContrast

    var theme: Theme {
      switch self {
      case .largerFont: Theme(font: .monospacedSystemFont(ofSize: 17, weight: .regular))
      case .moreContrast: Theme(increasesContrast: true)
      }
    }
  }

  /// Expects `changed` to draw byte for byte as `fresh` does.
  private static func expectSame(
    _ changed: PaneView, _ fresh: PaneView, sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let changedBitmap = try Rendering.bitmap(of: changed)
    let freshBitmap = try Rendering.bitmap(of: fresh)
    let length = freshBitmap.bytesPerRow * freshBitmap.pixelsHigh
    try #require(
      changedBitmap.bytesPerRow * changedBitmap.pixelsHigh == length,
      sourceLocation: sourceLocation)
    let changedBytes = try #require(changedBitmap.bitmapData, sourceLocation: sourceLocation)
    let freshBytes = try #require(freshBitmap.bitmapData, sourceLocation: sourceLocation)
    #expect(
      memcmp(changedBytes, freshBytes, length) == 0, "the pane keeps marks of how it looked",
      sourceLocation: sourceLocation)
  }

  /// A focused pane of 40 rows with the rings of ignored differences at rows 2, 3 and 6, the
  /// current block over rows 5 to 7, whose ring takes the color of the filled cell, and a
  /// collapsed run from row 10 to row 30.
  private static func pane(theme: Theme, appearance: NSAppearance) -> (PaneView, NSWindow) {
    let pane = PaneView(theme: theme)
    let content = CodeRows.content(count: 40)
    pane.content = PaneContent(
      text: content.text, lineNumbers: content.lineNumbers,
      blocks: [PaneBlock(rows: 5..<8, style: .tinted(.a))], ignoredDifferenceRows: [2, 3, 6])
    pane.collapsedRuns = [CollapsedRun(rows: 10..<30)]
    pane.currentBlock = 0
    let window = Rendering.host(
      pane, size: CGSize(width: 360, height: 300), appearance: appearance, isKey: true)
    window.makeFirstResponder(pane.documentView)
    return (pane, window)
  }
}
