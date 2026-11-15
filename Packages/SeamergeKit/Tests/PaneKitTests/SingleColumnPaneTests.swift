import AppKit
import Testing

@testable import PaneKit

/// A pane that shows both files of a comparison in one column: two columns of line numbers in
/// the gutter, the parts of a block each with its tint and mark and a hairline between them,
/// VoiceOver naming each row with its side and lines, and the triangle of the overview bar at
/// the middle of the marks of both parts.
@MainActor
@Suite struct SingleColumnPaneTests {
  /// A shared line, a block whose left line was replaced by two right ones, a removed line, an
  /// added line and a shared line again, numbered as a comparison numbers them.
  private static let content = PaneContent(
    text: ["shared", "old", "new", "newer", "removed", "added", "shared again"].joined(
      separator: "\n"),
    lineNumbers: (0..<7).map(Int32.init),
    sideLineNumbers: SideLineNumbers(
      left: [0, 1, -1, -1, 2, -1, 3], right: [0, -1, 1, 2, -1, 3, 4]),
    blocks: [
      PaneBlock(
        rows: 1..<4, style: .tinted(.a), marker: .changed,
        lowerPart: PaneBlockPart(firstRow: 2, style: .tinted(.b), marker: .changed)),
      PaneBlock(rows: 4..<5, style: .tinted(.a), marker: .removed),
      PaneBlock(rows: 5..<6, style: .tinted(.b), marker: .added),
    ])

  private static func pane(
    _ content: PaneContent = content, width: CGFloat = 360, appearance: NSAppearance? = nil
  ) -> (PaneView, NSWindow) {
    let pane = PaneView()
    pane.content = content
    let window = Rendering.host(
      pane, size: CGSize(width: width, height: 240),
      appearance: appearance ?? NSAppearance(named: .aqua))
    return (pane, window)
  }

  @Test func removedRowHasOnlyTheLeftNumberAddedOnlyTheRightAndSharedBoth() {
    let (pane, window) = Self.pane()
    defer { window.close() }

    let numbers = (0..<7).map { pane.gutterView.shownLineNumbers(ofRow: $0) }
    #expect(numbers == [[0, 0], [1, -1], [-1, 1], [-1, 2], [2, -1], [-1, 3], [3, 4]])
  }

  @Test func bothColumnsAreAsWideAsTheLargestNumberOfEitherSide() {
    let wide = PaneContent(
      text: "a\nb", lineNumbers: [0, 1],
      sideLineNumbers: SideLineNumbers(left: [8, -1], right: [-1, 12_344]))
    let (pane, window) = Self.pane(wide)
    defer { window.close() }
    let theme = pane.theme

    let digit =
      [theme.lineNumberFont, theme.currentLineNumberFont].map {
        ("0" as NSString).size(withAttributes: [.font: $0]).width
      }.max() ?? 0
    let width =
      Theme.gutterLeadingInset + 2 * 5 * digit + Theme.gutterNumberColumnSpacing
      + Theme.gutterNumberSpacing + Theme.markerSlotWidth
    #expect(pane.gutterView.fittingWidth == (width / Theme.layoutGrid).rounded(.up) * 4)
  }

  @Test func numbersStandInTheirOwnColumnAndTheOtherStaysEmpty() throws {
    let (pane, window) = Self.pane()
    defer { window.close() }
    let gutter = pane.gutterView
    let bitmap = try Rendering.bitmap(of: gutter)
    let digit =
      [pane.theme.lineNumberFont, pane.theme.currentLineNumberFont].map {
        ("0" as NSString).size(withAttributes: [.font: $0]).width
      }.max() ?? 0
    let columnWidth = CGFloat(Theme.minimumLineNumberDigits) * digit

    func hasInk(row: Int, column: Int) throws -> Bool {
      let rect = gutter.rect(ofRow: row)
      let ground = try Rendering.color(in: bitmap, at: CGPoint(x: 1, y: rect.midY))
      let start =
        Theme.gutterLeadingInset + CGFloat(column) * (columnWidth + Theme.gutterNumberColumnSpacing)
      return try stride(from: start, to: start + columnWidth, by: 0.5).contains { x in
        try Rendering.color(in: bitmap, at: CGPoint(x: x, y: rect.midY)) != ground
      }
    }
    for (row, columns) in [(0, [true, true]), (1, [true, false]), (2, [false, true])] {
      let ink = try [hasInk(row: row, column: 0), hasInk(row: row, column: 1)]
      #expect(ink == columns, "row \(row)")
    }
  }

  @Test func wrappedRowKeepsItsNumbersOnItsFirstScreenLineAndTheGutterItsWidth() throws {
    let long = String(repeating: "word ", count: 30)
    let content = PaneContent(
      text: "\(long)\nnext", lineNumbers: [0, 1],
      sideLineNumbers: SideLineNumbers(left: [0, -1], right: [0, 1]),
      blocks: [PaneBlock(rows: 1..<2, style: .tinted(.b), marker: .added)])
    let (unwrapped, unwrappedWindow) = Self.pane(content, width: 360)
    let width = unwrapped.gutterView.fittingWidth
    unwrappedWindow.close()
    let pane = PaneView()
    pane.wrapsLines = true
    pane.content = content
    let window = Rendering.host(pane, size: CGSize(width: 360, height: 240))
    defer { window.close() }
    let manager = try #require(pane.textView.textLayoutManager)
    manager.ensureLayout(for: manager.documentRange)
    pane.layoutSubtreeIfNeeded()

    let lines = pane.displayRows.lines(ofRows: 0..<1).count
    #expect(lines > 1)
    #expect(pane.gutterView.fittingWidth == width)
    #expect(pane.gutterView.rect(ofRow: 0).height == CGFloat(lines) * pane.theme.rowHeight)
    #expect(pane.gutterView.rect(ofRow: 1).minY == CGFloat(lines) * pane.theme.rowHeight)
    #expect(pane.gutterView.shownLineNumbers(ofRow: 1) == [-1, 1])
  }

  @Test func lowerPartHasTheTintTheMarkAndTheHighlightsOfItsSide() throws {
    let (pane, window) = Self.pane()
    defer { window.close() }
    let text = pane.textView

    #expect([1, 2, 3].map { text.style(ofRow: $0) } == [.tinted(.a), .tinted(.b), .tinted(.b)])
    let marks = (1..<4).map { row in
      pane.gutterView.marks(ofRow: row).map { entry -> String in
        guard case .marker(let marker, let style) = entry.mark else { return "other" }
        return "\(marker) \(style)"
      }
    }
    #expect(
      marks == [
        ["changed tinted(PaneKit.ColorRole.a)"], ["changed tinted(PaneKit.ColorRole.b)"], [],
      ])
    let highlights = PartHighlights([0: [7..<10, 11..<14]])
    pane.highlightProvider = highlights
    let runs = withExtendedLifetime(highlights) { text.changes(inRows: 1..<3).runs }
    #expect(runs.map(\.range) == [7..<10, 11..<14])
    let appearance = try #require(NSAppearance(named: .aqua))
    #expect(
      runs.map { Contrast.resolve($0.fill, in: appearance) } == [
        Contrast.resolve(pane.theme.runFill(for: .tinted(.a), isCurrent: false), in: appearance),
        Contrast.resolve(pane.theme.runFill(for: .tinted(.b), isCurrent: false), in: appearance),
      ])
  }

  @Test func hairlineDividesThePartsOfABlockLikeTwoBlocksThatTouch() throws {
    let (pane, window) = Self.pane()
    defer { window.close() }
    let appearance = try #require(NSAppearance(named: .aqua))
    let edges = pane.textView.painting(forRows: 0..<7).shadings.map(\.edges)

    #expect(edges.indices.filter { edges[$0].top != nil } == [1, 2, 4, 5])
    #expect(edges.indices.filter { edges[$0].bottom != nil } == [5])
    let between = pane.theme.edgeColor(
      between: .tinted(.a), and: .tinted(.b), isOnlyBoundary: false)
    #expect(
      Contrast.resolve(edges[2].top, in: appearance) == Contrast.resolve(between, in: appearance))
  }

  @Test func bothPartsOfTheCurrentBlockAreCurrent() throws {
    let (pane, window) = Self.pane()
    defer { window.close() }
    let appearance = try #require(NSAppearance(named: .aqua))
    pane.currentBlock = 0

    let fills = (1..<4).map {
      Contrast.resolve(pane.textView.shading(atRow: $0).fill, in: appearance)
    }
    let current = { (style: BlockStyle) in
      Contrast.resolve(
        pane.theme.rowFill(for: style, isFiller: false, isCurrent: true), in: appearance)
    }
    #expect(fills == [current(.tinted(.a)), current(.tinted(.b)), current(.tinted(.b))])
    #expect(
      fills[0]
        != Contrast.resolve(
          pane.theme.rowFill(for: .tinted(.a), isFiller: false, isCurrent: false), in: appearance))
  }

  @Test func voiceOverNamesEveryRowWithItsSideAndItsLines() throws {
    let (pane, window) = Self.pane()
    defer { window.close() }

    let rows = try #require(pane.gutterView.accessibilityChildren() as? [NSAccessibilityElement])
      .filter { $0.accessibilityRole() == .staticText }
    #expect(
      rows.map { "\($0.accessibilityLabel() ?? ""), \($0.accessibilityValue() as? String ?? "")" }
        == [
          "Unchanged, Line 1", "Removed, Line 2", "Added, Line 2", "Added, Line 3",
          "Removed, Line 3", "Added, Line 4", "Unchanged, Line 4 on the left, line 5 on the right",
        ])
    let gutterFrame = pane.gutterView.bounds
    #expect(rows.allSatisfy { gutterFrame.contains($0.accessibilityFrameInParentSpace()) })
  }

  @Test func marksAreNamedWithTheLinesOfTheirRow() throws {
    let (pane, window) = Self.pane()
    defer { window.close() }

    let marks = try #require(pane.gutterView.accessibilityChildren() as? [NSAccessibilityElement])
      .filter { $0.accessibilityRole() == .image }
    #expect(
      marks.map { "\($0.accessibilityLabel() ?? ""), \($0.accessibilityValue() as? String ?? "")" }
        == ["Changed, Line 2", "Changed, Line 2", "Removed, Line 3", "Added, Line 4"])
    #expect(pane.placeDescription(ofBlock: 2) == "Line 4")
  }

  @Test func lowerPartMovesWithAnEditAndGoesWhenItWouldStartAtTheEndOfItsBlock() {
    var content = PaneContent(
      text: "a\nb\nc\nd\ne", lineNumbers: (0..<5).map(Int32.init),
      blocks: [
        PaneBlock(
          rows: 1..<4, style: .tinted(.a),
          lowerPart: PaneBlockPart(firstRow: 3, style: .tinted(.b)))
      ])

    content.takeOver(
      RowChange(oldRows: 1..<2, newRows: 1..<3), replacing: 3..<3, length: 2,
      text: "a\nb\nx\nc\nd\ne")
    #expect(content.blocks[0].rows == 1..<5)
    #expect(content.blocks[0].lowerPart?.firstRow == 4)

    content.takeOver(
      RowChange(oldRows: 3..<5, newRows: 3..<4), replacing: 7..<9, length: 0,
      text: "a\nb\nx\nc\ne")
    #expect(content.blocks[0].rows == 1..<4)
    #expect(content.blocks[0].lowerPart == nil)
  }

  @Test func editInTheColumnDropsTheNumbersOfBothFilesAndTheGutterNumbersTheRows() {
    let (pane, window) = Self.pane()
    defer { window.close() }
    var content = Self.content

    content.takeOver(
      RowChange(oldRows: 0..<1, newRows: 0..<2), replacing: 6..<6, length: 2,
      text: "shared\nx\nold\nnew\nnewer\nremoved\nadded\nshared again")
    pane.content = content

    #expect(content.sideLineNumbers == nil)
    #expect((0..<8).map { pane.gutterView.shownLineNumbers(ofRow: $0) } == (0..<8).map { [$0] })
  }

  @Test func triangleOfTheOverviewBarPointsAtTheMiddleOfBothPartsOfTheCurrentBlock() throws {
    let appearance = try #require(NSAppearance(named: .aqua))
    let theme = Theme()
    let sample = SingleColumnSample(.transcoder)
    let pane = PaneView(theme: theme)
    pane.content = sample.content
    let bar = OverviewBar()
    bar.marks = sample.overviewMarks
    pane.overviewBar = bar
    let window = Rendering.host(
      pane, size: CGSize(width: 600, height: CGFloat(40) * theme.rowHeight),
      appearance: appearance)
    defer { window.close() }
    let block = sample.content.blocks.count - 1
    let (upper, lower) = sample.parts[block]
    let track = bar.convert(bar.rect(for: .knobSlot), to: pane)
    // The bar spreads the rows over its track, but none higher than in the text.
    let scale = min(track.height / CGFloat(bar.displayRows.lineCount), theme.rowHeight)
    func y(ofRow row: Double) -> CGFloat {
      track.minY + CGFloat(row) * scale
    }
    let x = bar.frame.minX + 1
    let ground = try Rendering.color(
      in: Rendering.bitmap(of: pane), at: CGPoint(x: x, y: y(ofRow: 1)))

    bar.currentBlock = block
    let bitmap = try Rendering.bitmap(of: pane)

    let middle = y(ofRow: Double(upper.lowerBound + lower.upperBound) / 2)
    let label = try #require(Contrast.resolve(.labelColor, in: appearance))
    let atMiddle = try Rendering.color(in: bitmap, at: CGPoint(x: x, y: middle))
    let triangle = Contrast.over(label, ground)
    #expect(abs(atMiddle.brightnessComponent - triangle.brightnessComponent) < 0.01)
    let middleOfUpper = y(ofRow: Double(upper.lowerBound + upper.upperBound) / 2)
    let atMiddleOfUpper = try Rendering.color(in: bitmap, at: CGPoint(x: x, y: middleOfUpper))
    #expect(atMiddleOfUpper == ground)
  }
}

/// Gives each block the highlights the test names.
@MainActor
private final class PartHighlights: PaneHighlightProvider {
  private let ranges: [Int: [Range<Int>]]

  init(_ ranges: [Int: [Range<Int>]]) {
    self.ranges = ranges
  }

  func highlights(forBlock block: Int) -> [Range<Int>] {
    ranges[block] ?? []
  }
}
