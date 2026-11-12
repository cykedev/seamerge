import AppKit
import PaneKit
import Testing

/// Draws the pictures for the visual review: every kind of block on real code, in every look.
@MainActor
@Suite struct PicturesTests {
  @Test(arguments: Look.all)
  func mergePanesArePictured(look: Look) throws {
    let theme = Theme(increasesContrast: look.increasesContrast)
    let layout = MergeLayout(merge: .transcoder, theme: theme)
    let window = Rendering.host(
      layout, size: layout.fittingSize(paneWidth: 520), appearance: look.appearance)
    defer { window.close() }
    let selected = layout.upperPanes[0]
    selected.documentView.setSelectedRange(shortSelection(in: selected.content))
    try Rendering.write(Rendering.bitmap(of: layout), named: "merge-\(look.name)")
  }

  /// Pictures a narrow selection on a row of every tint, the current block included, focused in
  /// the key window and without focus.
  @Test(arguments: Look.all, [true, false])
  func selectionOnEveryTintIsPictured(look: Look, isFocused: Bool) throws {
    let theme = Theme(increasesContrast: look.increasesContrast)
    let rows: [(text: String, style: BlockStyle)] = [
      ("let neutral = unchanged(text)", .unchanged),
      ("let incoming = changedBy(a)", .tinted(.a)),
      ("let ownSide = changedBy(b)", .tinted(.b)),
      ("let original = baseOf(change)", .original),
      ("let conflict = baseOf(open)", .tinted(.conflict)),
      ("let combined = sameIn(both)", .combined),
      ("let typed = byHand(result)", .handwritten),
      ("let current = changedBy(b)", .tinted(.b)),
    ]
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(
      text: rows.map(\.text).joined(separator: "\n"),
      lineNumbers: rows.indices.map { Int32($0) },
      blocks: rows.indices.dropFirst().map { PaneBlock(rows: $0..<$0 + 1, style: rows[$0].style) })
    pane.currentBlock = rows.count - 2
    let window = Rendering.host(
      pane, size: CGSize(width: 420, height: 180), appearance: look.appearance, isKey: isFocused)
    defer { window.close() }
    window.makeFirstResponder(pane.documentView)
    var start = 0
    var ranges: [NSValue] = []
    for row in rows {
      ranges.append(NSValue(range: NSRange(location: start + 4, length: 10)))
      start += row.text.utf16.count + 1
    }
    pane.documentView.setSelectedRanges(ranges, affinity: .downstream, stillSelecting: false)
    try Rendering.write(
      Rendering.bitmap(of: pane),
      named: "selection-\(isFocused ? "active" : "inactive")-\(look.name)")
  }

  @Test func panesWithTheBaseHiddenArePictured() throws {
    for look in Look.all.prefix(2) {
      let theme = Theme(increasesContrast: look.increasesContrast)
      let layout = MergeLayout(merge: .transcoder, theme: theme, baseHidden: true)
      let window = Rendering.host(
        layout, size: layout.fittingSize(paneWidth: 700), appearance: look.appearance)
      try Rendering.write(Rendering.bitmap(of: layout), named: "base-hidden-\(look.name)")
      window.close()
    }
  }

  @Test func comparisonIsPictured() throws {
    for look in Look.all {
      let theme = Theme(increasesContrast: look.increasesContrast)
      let layout = MergeLayout(diffOf: .transcoder, theme: theme)
      let window = Rendering.host(
        layout, size: layout.fittingSize(paneWidth: 700), appearance: look.appearance)
      try Rendering.write(Rendering.bitmap(of: layout), named: "diff-\(look.name)")
      window.close()
    }
  }

  /// A selection from the middle of the third row, which A changed, to the middle of the
  /// fourth, which no side changed.
  private func shortSelection(in content: PaneContent) -> NSRange {
    let rows = content.text.split(separator: "\n", omittingEmptySubsequences: false)
    let rowStarts = rows.reduce(into: [0]) { starts, row in
      starts.append(starts[starts.count - 1] + row.utf16.count + 1)
    }
    let start = rowStarts[2] + 20
    return NSRange(location: start, length: rowStarts[4] + 2 - start)
  }
}
