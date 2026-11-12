import AppKit
import PaneKit
import Testing

/// Checks the narrowest width of a pane, which the window keeps its panes from going below.
@MainActor
@Suite struct MinimumWidthTests {
  @Test(arguments: [false, true])
  func paneAtItsMinimumWidthShowsTwentyCharactersBesideItsGutter(hasBar: Bool) throws {
    let theme = Theme()
    let pane = PaneView(theme: theme)
    pane.content = CodeRows.content(count: 12_000, length: 120)
    if hasBar {
      pane.overviewBar = OverviewBar()
    }
    let window = Rendering.host(
      pane, size: CGSize(width: pane.minimumWidth, height: 200))
    defer { window.close() }
    let characterWidth = ("0" as NSString).size(withAttributes: [.font: theme.font]).width
    #expect(pane.documentView.visibleRect.width >= 20 * characterWidth + 2 * 12)
    #expect(pane.minimumWidth.truncatingRemainder(dividingBy: 4) == 0)
  }
}
