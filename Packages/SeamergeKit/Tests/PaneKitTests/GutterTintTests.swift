import AppKit
import Testing

@testable import PaneKit

/// Checks that the tint of every row runs from the left edge of the pane to its text: the gutter
/// shows the same fill and the same hairlines as the text beside it, for every kind of row, and
/// keeps them below the sign that collapses a run; only the filled cells of the current block lie
/// on top.
@MainActor
@Suite struct GutterTintTests {
  /// One row of every kind, from the top: plain, a block of A with a filler row, plain, an open
  /// conflict on the base, the original, a change both sides made alike, a row typed by hand, a
  /// preview of A, and plain.
  private static let lines = [
    "let plain = 0", "let a = 1", "let aa = 2", "", "let plain = 3", "let conflict = 4",
    "let original = 5", "let combined = 6", "let typed = 7", "let preview = 8", "let plain = 9",
  ]

  private static func pane(
    appearance: NSAppearance, height: CGFloat = 280
  ) -> (PaneView, NSWindow) {
    let text = lines.joined(separator: "\n")
    let pane = PaneView()
    pane.content = PaneContent(
      text: text, lineNumbers: [0, 1, 2, -1, 3, 4, 5, 6, 7, 8, 9],
      blocks: [
        PaneBlock(rows: 1..<4, style: .tinted(.a), marker: .changed),
        PaneBlock(rows: 5..<6, style: .tinted(.conflict), conflict: .open),
        PaneBlock(rows: 6..<7, style: .original),
        PaneBlock(rows: 7..<8, style: .combined),
      ])
    let previewStart = lines[..<9].reduce(0) { $0 + $1.utf16.count + 1 }
    pane.setBlocks(
      pane.content.blocks,
      previews: [PanePreview(range: previewStart..<previewStart + lines[9].utf16.count, role: .a)],
      rowTints: [8: .handwritten])
    let window = Rendering.host(
      pane, size: CGSize(width: 360, height: height), appearance: appearance)
    return (pane, window)
  }

  @Test(arguments: Look.all)
  func everyRowHasTheSameFillInTheGutterAsBesideItsText(look: Look) throws {
    let (pane, window) = Self.pane(appearance: look.appearance)
    defer { window.close() }
    pane.theme = Theme(increasesContrast: look.increasesContrast)
    let bitmap = try Rendering.bitmap(of: pane)
    let ground = try Rendering.color(in: bitmap, at: CGPoint(x: 2, y: middle(of: 0, pane)))
    for row in Self.lines.indices {
      let y = middle(of: row, pane)
      let gutter = try Rendering.color(in: bitmap, at: CGPoint(x: 2, y: y))
      let text = try Rendering.color(in: bitmap, at: CGPoint(x: pane.bounds.maxX - 4, y: y))
      #expect(difference(gutter, text) < 0.02, "row \(row): \(gutter) beside \(text)")
      let isTinted = ![0, 4, 10].contains(row)
      #expect(
        (difference(gutter, ground) > 0.01) == isTinted, "row \(row) is tinted: \(isTinted)")
    }
  }

  @Test(arguments: Look.all)
  func hairlinesRunThroughTheGutterOnTheSamePixelRow(look: Look) throws {
    let (pane, window) = Self.pane(appearance: look.appearance)
    defer { window.close() }
    pane.theme = Theme(increasesContrast: look.increasesContrast)
    let bitmap = try Rendering.bitmap(of: pane)
    let pixel = bitmap.size.width / CGFloat(bitmap.pixelsWide)
    let rowHeight = pane.theme.rowHeight
    // The top edges of the block of A, the conflict, the original and the combined block, and
    // the bottom edge of the block of A, each in the middle of its pixel row.
    // Each edge with the direction into its own row, where the probe beside it lies.
    let edges =
      [1, 5, 6, 7].map { (CGFloat($0) * rowHeight + pixel / 2, CGFloat(1)) }
      + [(4 * rowHeight - pixel / 2, CGFloat(-1))]
    for (y, inward) in edges {
      let gutter = try Rendering.color(in: bitmap, at: CGPoint(x: 2, y: y))
      let text = try Rendering.color(in: bitmap, at: CGPoint(x: pane.bounds.maxX - 4, y: y))
      let inside = try Rendering.color(
        in: bitmap, at: CGPoint(x: 2, y: y + inward * 2 * pixel))
      #expect(difference(gutter, text) < 0.02, "edge at \(y): \(gutter) beside \(text)")
      #expect(difference(gutter, inside) > 0.01, "the edge at \(y) shows in the gutter")
    }
  }

  /// Scrolled by a fraction of a point, the gutter shows every pixel row around the edges of the
  /// blocks as the text beside it does, wherever the clip view puts the text on the pixels; told
  /// an offset a quarter pixel off, the gutter still puts its rows on the pixels of the text.
  @Test(arguments: [0.5, 13.25] as [CGFloat])
  func hairlinesStayOnTheSamePixelRowWhenScrolledByAFraction(offset: CGFloat) throws {
    let appearance = try #require(NSAppearance(named: .aqua))
    let (pane, window) = Self.pane(appearance: appearance, height: 120)
    defer { window.close() }
    pane.documentView.scroll(CGPoint(x: 0, y: offset))
    let shown = pane.documentView.visibleRect.minY
    let pixel = 1 / window.backingScaleFactor
    #expect(abs(shown - offset) <= pixel, "scrolled to \(shown)")
    #expect(try mismatchesAtTheEdges(of: pane, scrolledTo: shown).isEmpty)
    pane.gutterView.scrollOffset = shown + pixel / 4
    #expect(try mismatchesAtTheEdges(of: pane, scrolledTo: shown).isEmpty, "a quarter pixel off")
  }

  /// The pixel rows around the edges of the blocks of `pane`, scrolled to `offset`, in which the
  /// gutter differs from the text beside it.
  private func mismatchesAtTheEdges(of pane: PaneView, scrolledTo offset: CGFloat) throws
    -> [String]
  {
    let bitmap = try Rendering.bitmap(of: pane)
    let pixel = bitmap.size.width / CGFloat(bitmap.pixelsWide)
    var mismatches: [String] = []
    for boundary in [1, 4, 5, 6] {
      let edge = CGFloat(boundary) * pane.theme.rowHeight - offset
      for step in -3...3 {
        let y = edge + (CGFloat(step) + 0.5) * pixel
        guard y > 0, y < pane.bounds.height else { continue }
        let gutter = try Rendering.color(in: bitmap, at: CGPoint(x: 2, y: y))
        let text = try Rendering.color(in: bitmap, at: CGPoint(x: pane.bounds.maxX - 4, y: y))
        if difference(gutter, text) >= 0.02 {
          mismatches.append("y \(y): \(gutter) beside \(text)")
        }
      }
    }
    return mismatches
  }

  @Test func filledCellOfTheCurrentBlockEndsItsHairlines() throws {
    let appearance = try #require(NSAppearance(named: .aqua))
    let (pane, window) = Self.pane(appearance: appearance)
    defer { window.close() }
    pane.currentBlock = 0
    let bitmap = try Rendering.bitmap(of: pane)
    let pixel = bitmap.size.width / CGFloat(bitmap.pixelsWide)
    let top = pane.theme.rowHeight + pixel / 2
    let cell = try Rendering.color(in: bitmap, at: CGPoint(x: 2, y: middle(of: 1, pane)))
    let edge = try Rendering.color(in: bitmap, at: CGPoint(x: 2, y: top))
    let text = try Rendering.color(in: bitmap, at: CGPoint(x: pane.bounds.maxX - 4, y: top))
    #expect(difference(edge, cell) < 0.02, "the cell covers the top edge in the gutter")
    #expect(difference(text, cell) > 0.05, "the top edge still runs beside the text")
  }

  /// The sign that collapses an expanded run stands on the ground of its row, which looks the
  /// same as without the pointer around it; the run starts on a tinted row here, the hardest
  /// case.
  @Test(arguments: Look.all)
  func signThatCollapsesARunStandsOnTheTintOfItsRow(look: Look) throws {
    let (pane, window) = Self.pane(appearance: look.appearance)
    defer { window.close() }
    pane.theme = Theme(increasesContrast: look.increasesContrast)
    pane.expandedRuns = [CollapsedRun(rows: 5..<8)]
    let gutter = pane.gutterView
    let slot = gutter.markerSlot(0, in: gutter.rect(ofRow: 5))
    let corners = [
      CGPoint(x: slot.minX + 1, y: slot.minY + 2), CGPoint(x: slot.maxX - 1, y: slot.maxY - 2),
    ]
    let plain = try Rendering.bitmap(of: pane)
    gutter.pointerMoved(to: CGPoint(x: 10, y: middle(of: 6, pane)))
    #expect(gutter.isShowingCollapseSign(ofRun: 0))
    let hovered = try Rendering.bitmap(of: pane)
    try Rendering.write(hovered, named: "gutter-hover-\(look.name)")
    let text = try Rendering.color(
      in: plain, at: CGPoint(x: pane.bounds.maxX - 4, y: middle(of: 5, pane)))
    for corner in corners {
      let before = try Rendering.color(in: plain, at: corner)
      let after = try Rendering.color(in: hovered, at: corner)
      #expect(difference(before, after) < 0.02, "at \(corner): \(after) instead of \(before)")
      #expect(difference(after, text) < 0.02, "at \(corner): \(after) beside \(text)")
    }
  }

  /// Pictures the bands of a seam beside the tinted gutter of the pane on its right, with a
  /// current block, so that the review sees that the tints meet without a gap and do not overlap.
  @Test(arguments: Look.all)
  func seamBesideTheTintedGutterIsPictured(look: Look) throws {
    let (layout, window) = ConnectedLayout.hosted(height: 360, appearance: look.appearance)
    defer { window.close() }
    let theme = Theme(increasesContrast: look.increasesContrast)
    layout.left.theme = theme
    layout.right.theme = theme
    layout.seam.theme = theme
    layout.left.currentBlock = 2
    layout.right.currentBlock = 2
    let bitmap = try Rendering.bitmap(of: layout)
    try Rendering.write(bitmap, named: "seam-\(look.name)")
    // The band of the insertion, which is not current, ends in the tint of the gutter on its
    // right without a gap, beside the separator at the edge of the seam.
    let rows = layout.right.content.blocks[1].rows
    let y = layout.convert(
      CGPoint(x: 0, y: layout.right.verticalSpan(ofRows: rows).lowerBound + 1.5 * theme.rowHeight),
      from: layout.right.documentView
    ).y
    let pixel = 1 / window.backingScaleFactor
    let bandEnd = try Rendering.color(
      in: bitmap, at: CGPoint(x: layout.seam.frame.maxX - 1.5 * pixel, y: y))
    let gutter = try Rendering.color(in: bitmap, at: CGPoint(x: layout.right.frame.minX + 2, y: y))
    #expect(difference(bandEnd, gutter) < 0.03, "\(bandEnd) beside \(gutter)")
  }

  private func middle(of row: Int, _ pane: PaneView) -> CGFloat {
    (CGFloat(row) + 0.5) * pane.theme.rowHeight
  }

  private func difference(_ first: NSColor, _ second: NSColor) -> CGFloat {
    max(
      abs(first.redComponent - second.redComponent),
      abs(first.greenComponent - second.greenComponent),
      abs(first.blueComponent - second.blueComponent))
  }
}
