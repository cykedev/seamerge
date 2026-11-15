import AppKit
import PaneKit
import Testing

/// Draws the pictures of a comparison in a single column for the visual review: the gutter with
/// two columns of line numbers, the parts of each block with the hairline between them, and the
/// overview bar with the marks of the parts one below the other.
@MainActor
@Suite struct SingleColumnPicturesTests {
  /// Hosts the single column of the sample comparison in a pane of `width` with an overview bar.
  private static func pane(
    _ sample: SingleColumnSample, theme: Theme, look: Look, width: CGFloat = 760,
    wrapsLines: Bool = false, isKey: Bool = false
  ) -> (PaneView, SingleColumnHighlights, NSWindow) {
    let pane = PaneView(theme: theme)
    let highlights = SingleColumnHighlights(sample)
    pane.highlightProvider = highlights
    pane.content = sample.content
    pane.wrapsLines = wrapsLines
    let bar = OverviewBar()
    bar.theme = theme
    bar.marks = sample.overviewMarks
    pane.overviewBar = bar
    pane.currentBlock = sample.content.blocks.count - 1
    bar.currentBlock = pane.currentBlock
    let height = CGFloat(sample.content.lineNumbers.count + 2) * theme.rowHeight
    let window = Rendering.host(
      pane, size: CGSize(width: width, height: height), appearance: look.appearance, isKey: isKey)
    return (pane, highlights, window)
  }

  @Test(arguments: Look.all)
  func singleColumnIsPictured(look: Look) throws {
    let theme = Theme(increasesContrast: look.increasesContrast)
    let (pane, highlights, window) = Self.pane(
      SingleColumnSample(.transcoder), theme: theme, look: look)
    defer { window.close() }
    defer { withExtendedLifetime(highlights) {} }
    try Rendering.write(Rendering.bitmap(of: pane), named: "single-column-\(look.name)")
  }

  /// Pictures the column in a narrow pane whose long lines wrap: the numbers of both files stay
  /// on the first screen line of their row.
  @Test(arguments: Look.all)
  func wrappedSingleColumnIsPictured(look: Look) throws {
    let theme = Theme(increasesContrast: look.increasesContrast)
    let (pane, highlights, window) = Self.pane(
      SingleColumnSample(.transcoder), theme: theme, look: look, width: 420, wrapsLines: true)
    defer { window.close() }
    defer { withExtendedLifetime(highlights) {} }
    try Rendering.write(
      Rendering.bitmap(of: pane), named: "single-column-wrapped-\(look.name)")
  }

  /// Pictures the column without color, where the marks of the overview bar keep their lanes and
  /// the gutter its typed marks, and focused in the key window, where the current block shows in
  /// the accent color.
  @Test func singleColumnWithoutColorAndFocusedIsPictured() throws {
    let look = Look.all[0]
    let theme = Theme(differentiatesWithoutColor: true)
    let (pane, highlights, window) = Self.pane(
      SingleColumnSample(.transcoder), theme: theme, look: look, isKey: true)
    defer { window.close() }
    window.makeFirstResponder(pane.documentView)
    defer { withExtendedLifetime(highlights) {} }
    try Rendering.write(
      Rendering.bitmap(of: pane), named: "single-column-without-color-focused-light")
  }
}
