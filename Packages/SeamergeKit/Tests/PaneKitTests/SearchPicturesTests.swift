import AppKit
import Testing

@testable import PaneKit

/// Draws the marks of a search for the visual review, on real code: the outline of every match,
/// the current match selected, and the strokes in the overview bars, in every look.
@MainActor
@Suite struct SearchPicturesTests {
  @Test(arguments: Look.all)
  func matchesAndTheirStrokesArePictured(look: Look) throws {
    try picture(theme: Theme(increasesContrast: look.increasesContrast), look: look, width: 520)
  }

  @Test func matchesArePicturedWithoutColorAndInTheNarrowestPanes() throws {
    let look = Look.all[1]
    try picture(
      theme: Theme(differentiatesWithoutColor: true), look: look, width: 520,
      name: "search-without-color-\(look.name)")
    try picture(
      theme: Theme(), look: look, width: 260, name: "search-narrow-\(look.name)")
  }

  /// Pictures the merge of the transcoder with every "encoding" marked, the one in the fourth
  /// row of B current, in panes of `width`.
  private func picture(theme: Theme, look: Look, width: CGFloat, name: String? = nil) throws {
    let layout = MergeLayout(merge: .transcoder, theme: theme)
    let panes = layout.upperPanes + [layout.resultPane].compactMap(\.self)
    for pane in [layout.upperPanes.last, layout.resultPane].compactMap(\.self) {
      let bar = OverviewBar()
      bar.theme = theme
      bar.marks = pane.content.blocks.enumerated().map { index, block in
        OverviewMark(
          rows: block.rows, style: block.style, placement: .fullWidth, block: index,
          accessibilityLabel: "Block \(index + 1)")
      }
      pane.overviewBar = bar
    }
    var current: (pane: PaneView, range: Range<Int>)?
    for pane in panes {
      let text = pane.documentView.string as NSString
      var matches: [Range<Int>] = []
      var start = 0
      while start < text.length {
        let found = text.range(
          of: "encoding", options: .caseInsensitive,
          range: NSRange(location: start, length: text.length - start))
        guard found.location != NSNotFound else { break }
        matches.append(found.location..<NSMaxRange(found))
        start = NSMaxRange(found)
      }
      pane.textView.searchMatches = matches
      pane.overviewBar?.matchRows = IndexSet(
        matches.map { pane.row(containingOffset: $0.lowerBound) })
      if pane === layout.upperPanes.last, matches.count > 3 {
        current = (pane, matches[3])
      }
    }
    let window = Rendering.host(
      layout, size: layout.fittingSize(paneWidth: width), appearance: look.appearance,
      isKey: true)
    defer { window.close() }
    if let current {
      window.makeFirstResponder(current.pane.documentView)
      current.pane.documentView.setSelectedRange(NSRange(current.range))
    }
    try Rendering.write(Rendering.bitmap(of: layout), named: name ?? "search-\(look.name)")
  }
}
