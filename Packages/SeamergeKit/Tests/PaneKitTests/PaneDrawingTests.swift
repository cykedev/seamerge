import AppKit
import PaneKit
import Testing

/// Checks what a pane draws, pixel by pixel: row fills, the current block, the place of the
/// text in its row and the line numbers beside it.
@MainActor
@Suite struct PaneDrawingTests {
  private let theme = Theme()
  private let appearance = Look.all[0].appearance

  @Test func rowFillsReachAcrossThePaneOnEmptyRowsAndAfterScrollingSideways() throws {
    let longLine = String(repeating: "abcdefghij", count: 40)
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(
      text: "\n\(longLine)\n\n", lineNumbers: [0, 1, -1, -1],
      blocks: [PaneBlock(rows: 0..<4, style: .tinted(.a), marker: .added)])
    let window = Rendering.host(pane, size: CGSize(width: 400, height: 200), appearance: appearance)
    defer { window.close() }
    let lineFill = expectedFill(.tinted(.a), isFiller: false)
    let fillerFill = expectedFill(.tinted(.a), isFiller: true)
    let ground = expectedFill(.unchanged, isFiller: false)
    var bitmap = try Rendering.bitmap(of: pane)
    try expectColor(in: bitmap, at: CGPoint(x: 390, y: row(0)), lineFill)
    try expectColor(in: bitmap, at: CGPoint(x: 390, y: row(2)), fillerFill)
    try expectColor(in: bitmap, at: CGPoint(x: 390, y: row(3)), fillerFill, "empty last row")
    try expectColor(in: bitmap, at: CGPoint(x: 390, y: row(4)), ground, "below the last row")

    let textView = pane.documentView
    textView.scroll(CGPoint(x: textView.frame.width, y: 0))
    bitmap = try Rendering.bitmap(of: pane)
    let left = pane.bounds.width - textView.visibleRect.width + 2
    for x in [left, 390] {
      try expectColor(in: bitmap, at: CGPoint(x: x, y: row(0)), lineFill, "scrolled, x \(x)")
      try expectColor(in: bitmap, at: CGPoint(x: x, y: row(3)), fillerFill, "scrolled, x \(x)")
    }
  }

  @Test func currentBlockIsTintedMoreStronglyWithFilledLineNumberCells() throws {
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(
      text: "first\nsecond\nthird", lineNumbers: [0, 1, 2],
      blocks: [
        PaneBlock(rows: 0..<1, style: .tinted(.b), marker: .changed),
        PaneBlock(rows: 2..<3, style: .tinted(.b), marker: .changed),
      ])
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 100), appearance: appearance)
    defer { window.close() }
    let plain = expectedFill(.tinted(.b), isFiller: false)
    let current = expectedFill(.tinted(.b), isFiller: false, isCurrent: true)
    let ground = expectedFill(.unchanged, isFiller: false)

    pane.currentBlock = 0
    var bitmap = try Rendering.bitmap(of: pane)
    try expectColor(in: bitmap, at: CGPoint(x: 290, y: row(0)), current, "current text area")
    try expectColor(in: bitmap, at: CGPoint(x: 2, y: row(0)), current, "current gutter cell")
    try expectColor(in: bitmap, at: CGPoint(x: 290, y: row(2)), plain)
    try expectColor(in: bitmap, at: CGPoint(x: 2, y: row(2)), ground, "gutter of another block")

    pane.currentBlock = 1
    bitmap = try Rendering.bitmap(of: pane)
    try expectColor(in: bitmap, at: CGPoint(x: 290, y: row(0)), plain, "former current block")
    try expectColor(in: bitmap, at: CGPoint(x: 2, y: row(0)), ground, "former current cell")
    try expectColor(in: bitmap, at: CGPoint(x: 290, y: row(2)), current)
  }

  @Test func textSitsInTheMiddleOfItsRow() throws {
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(text: "HHHHHHHH", lineNumbers: [0])
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 60), appearance: appearance)
    defer { window.close() }
    let bitmap = try Rendering.bitmap(of: pane)
    let textStart = pane.bounds.width - pane.documentView.visibleRect.width
    let ink = try inkExtent(in: bitmap, xs: textStart + 14..<textStart + 40, rows: 0..<1)
    let rowMiddle = theme.rowHeight / 2
    #expect(abs((ink.lowerBound + ink.upperBound) / 2 - rowMiddle) <= 1, "ink \(ink)")
  }

  @Test func lineNumbersShareTheBaselineOfTheText() throws {
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(text: "\n\n\n\n\n\n\n8888", lineNumbers: Array(0..<8))
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 200), appearance: appearance)
    defer { window.close() }
    let bitmap = try Rendering.bitmap(of: pane)
    let textStart = pane.bounds.width - pane.documentView.visibleRect.width
    let gutterDigit = try inkExtent(in: bitmap, xs: 0..<textStart, rows: 7..<8)
    let textDigits = try inkExtent(in: bitmap, xs: textStart..<textStart + 60, rows: 7..<8)
    #expect(abs(gutterDigit.upperBound - textDigits.upperBound) <= 0.5)
  }

  @Test func highlightsAreAskedForOnlyForTheFewBlocksThatTextKitLaysOut() throws {
    let rowCount = 2_000
    let provider = RecordingHighlights()
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(
      text: Array(repeating: "changed line", count: rowCount).joined(separator: "\n"),
      lineNumbers: (0..<Int32(rowCount)).map { $0 },
      blocks: (0..<rowCount).map { PaneBlock(rows: $0..<$0 + 1, style: .tinted(.a)) })
    pane.highlightProvider = provider
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 200), appearance: appearance)
    defer { window.close() }
    _ = try Rendering.bitmap(of: pane)
    #expect(!provider.requestedBlocks.isEmpty)
    // TextKit lays out the visible rows and a few at the end, to place the end of the text.
    #expect(provider.requestedBlocks.count < rowCount / 10, "\(provider.requestedBlocks)")
    #expect(provider.requestedBlocks.count == Set(provider.requestedBlocks).count)
  }

  @Test func changedRunIsFilledWithinItsLine() throws {
    let provider = RecordingHighlights(runs: [0: [4..<12]])
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(
      text: "let changed = 1", lineNumbers: [0],
      blocks: [PaneBlock(rows: 0..<1, style: .tinted(.a), marker: .changed)])
    pane.highlightProvider = provider
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 60), appearance: appearance)
    defer { window.close() }
    let bitmap = try Rendering.bitmap(of: pane)
    let textStart = pane.bounds.width - pane.documentView.visibleRect.width + 12
    let characterWidth = ("0" as NSString).size(withAttributes: [.font: theme.font]).width
    let runColor = try Rendering.color(
      in: bitmap, at: CGPoint(x: textStart + 7.5 * characterWidth, y: row(0)))
    let rowColor = try Rendering.color(in: bitmap, at: CGPoint(x: 290, y: row(0)))
    #expect(Contrast.ratio(runColor, rowColor) > 1.1, "\(runColor) against \(rowColor)")
  }

  @Test func removedTextIsMarkedWithABarBetweenTheCharacters() throws {
    let provider = RecordingHighlights(runs: [0: [4..<4]])
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(
      text: "let value = 1", lineNumbers: [0],
      blocks: [PaneBlock(rows: 0..<1, style: .tinted(.a), marker: .changed)])
    pane.highlightProvider = provider
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 60), appearance: appearance)
    defer { window.close() }
    let bitmap = try Rendering.bitmap(of: pane)
    let textStart = pane.bounds.width - pane.documentView.visibleRect.width + 12
    let characterWidth = ("0" as NSString).size(withAttributes: [.font: theme.font]).width
    let mark = Contrast.over(
      Contrast.resolve(theme.markerColor(for: .tinted(.a)), in: appearance), .white)
    // The mark stands in the gap between "let" and "value", where the space was kept and the
    // removed text would have been, centered in its row.
    let markColumns = try (0..<Int(6 * characterWidth)).compactMap { step -> CGFloat? in
      let x = textStart + CGFloat(step)
      let color = try Rendering.color(in: bitmap, at: CGPoint(x: x, y: row(0)))
      return isClose(color, mark) ? x : nil
    }
    let first = try #require(markColumns.first)
    let last = try #require(markColumns.last)
    #expect(first >= textStart + 3 * characterWidth && last <= textStart + 4 * characterWidth + 1)
    for y in [1, theme.rowHeight - 1] {
      let color = try Rendering.color(in: bitmap, at: CGPoint(x: (first + last) / 2, y: y))
      #expect(!isClose(color, mark), "mark reaches y \(y) of a row of \(theme.rowHeight)")
    }
  }

  private func isClose(_ color: NSColor, _ other: NSColor) -> Bool {
    max(
      abs(color.redComponent - other.redComponent),
      abs(color.greenComponent - other.greenComponent),
      abs(color.blueComponent - other.blueComponent)) < 0.05
  }

  @Test func selectionLiesTranslucentAboveTheTintOfItsRow() throws {
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(
      text: "let selected = 1", lineNumbers: [0],
      blocks: [PaneBlock(rows: 0..<1, style: .tinted(.b), marker: .changed)])
    let window = Rendering.host(
      pane, size: CGSize(width: 300, height: 60), appearance: appearance, isKey: true)
    defer { window.close() }
    window.makeFirstResponder(pane.documentView)
    pane.documentView.setSelectedRange(NSRange(location: 4, length: 8))
    let bitmap = try Rendering.bitmap(of: pane)
    let textStart = pane.bounds.width - pane.documentView.visibleRect.width + 12
    let characterWidth = ("0" as NSString).size(withAttributes: [.font: theme.font]).width
    let row = expectedFill(.tinted(.b), isFiller: false)
    let selected = Contrast.over(
      Contrast.resolve(theme.selectionFill(isEmphasized: true), in: appearance), row)
    // Within "selected", above its glyphs.
    try expectColor(
      in: bitmap, at: CGPoint(x: textStart + 8 * characterWidth, y: 2), selected,
      "selection over the tint")
    try expectColor(in: bitmap, at: CGPoint(x: 290, y: 2), row, "tint beside the selection")
  }

  @Test func removalWithinAWordIsMarkedExactlyThere() throws {
    let provider = RecordingHighlights(runs: [0: [6..<6]])
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(
      text: "let value = 1", lineNumbers: [0],
      blocks: [PaneBlock(rows: 0..<1, style: .tinted(.a), marker: .changed)])
    pane.highlightProvider = provider
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 60), appearance: appearance)
    defer { window.close() }
    let bitmap = try Rendering.bitmap(of: pane)
    let textStart = pane.bounds.width - pane.documentView.visibleRect.width + 12
    let characterWidth = ("0" as NSString).size(withAttributes: [.font: theme.font]).width
    let mark = Contrast.over(
      Contrast.resolve(theme.markerColor(for: .tinted(.a)), in: appearance), .white)
    let columns = try markColumns(in: bitmap, from: textStart, width: 10 * characterWidth, mark)
    let middle = try (#require(columns.first) + #require(columns.last)) / 2
    // Between "va" and "lue", not moved to the start of the word.
    #expect(abs(middle - (textStart + 6 * characterWidth)) <= 1.5, "mark at \(middle)")
  }

  @Test func selectionRedrawsWhenItShrinksVanishesOrLosesFocus() throws {
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(
      text: "let selected = 1", lineNumbers: [0],
      blocks: [PaneBlock(rows: 0..<1, style: .tinted(.b), marker: .changed)])
    let window = Rendering.host(
      pane, size: CGSize(width: 300, height: 60), appearance: appearance, isKey: true)
    defer { window.close() }
    let keyWindow = try #require(window as? KeyWindow)
    window.makeFirstResponder(pane.documentView)
    let textStart = pane.bounds.width - pane.documentView.visibleRect.width + 12
    let characterWidth = ("0" as NSString).size(withAttributes: [.font: theme.font]).width
    let row = expectedFill(.tinted(.b), isFiller: false)
    func selected(_ isEmphasized: Bool) -> NSColor {
      Contrast.over(
        Contrast.resolve(theme.selectionFill(isEmphasized: isEmphasized), in: appearance), row)
    }
    let inside = CGPoint(x: textStart + 4.5 * characterWidth, y: 2)
    let end = CGPoint(x: textStart + 10.5 * characterWidth, y: 2)

    pane.documentView.setSelectedRange(NSRange(location: 4, length: 8))
    try expectColor(in: Rendering.bitmap(of: pane), at: end, selected(true), "selected")

    pane.documentView.setSelectedRange(NSRange(location: 4, length: 2))
    var bitmap = try Rendering.bitmap(of: pane)
    try expectColor(in: bitmap, at: end, row, "after shrinking")
    try expectColor(in: bitmap, at: inside, selected(true), "still selected")

    keyWindow.actsAsKey = false
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    try expectColor(
      in: Rendering.bitmap(of: pane), at: inside, selected(false), "in a window without focus")

    pane.documentView.setSelectedRange(NSRange(location: 4, length: 0))
    bitmap = try Rendering.bitmap(of: pane)
    try expectColor(in: bitmap, at: inside, row, "after clearing")
  }

  /// The columns of `bitmap` along the middle of the first row, from `start` over `width`, whose
  /// color is close to `mark`.
  private func markColumns(
    in bitmap: NSBitmapImageRep, from start: CGFloat, width: CGFloat, _ mark: NSColor
  ) throws -> [CGFloat] {
    try stride(from: start, to: start + width, by: 0.5).compactMap { x in
      isClose(try Rendering.color(in: bitmap, at: CGPoint(x: x, y: row(0))), mark) ? x : nil
    }
  }

  /// The middle of `row`, in the pane's coordinates.
  private func row(_ row: Int) -> CGFloat {
    (CGFloat(row) + 0.5) * theme.rowHeight
  }

  private func expectedFill(_ style: BlockStyle, isFiller: Bool, isCurrent: Bool = false)
    -> NSColor
  {
    let ground = Contrast.over(
      Contrast.resolve(.textBackgroundColor, in: appearance), NSColor.white)
    return Contrast.over(
      Contrast.resolve(
        theme.rowFill(for: style, isFiller: isFiller, isCurrent: isCurrent), in: appearance),
      ground)
  }

  private func expectColor(
    in bitmap: NSBitmapImageRep, at point: CGPoint, _ expected: NSColor, _ comment: String = "",
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let actual = try Rendering.color(in: bitmap, at: point)
    let difference = max(
      abs(actual.redComponent - expected.redComponent),
      abs(actual.greenComponent - expected.greenComponent),
      abs(actual.blueComponent - expected.blueComponent))
    #expect(
      difference < 0.02, "\(comment) at \(point): \(actual) instead of \(expected)",
      sourceLocation: sourceLocation)
  }

  /// The vertical extent of dark pixels within `xs` and `rows`, relative to the top of the
  /// first row.
  private func inkExtent(in bitmap: NSBitmapImageRep, xs: Range<CGFloat>, rows: Range<Int>)
    throws -> ClosedRange<CGFloat>
  {
    let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
    let top = CGFloat(rows.lowerBound) * theme.rowHeight
    var inked: [CGFloat] = []
    for pixelY in Int(top * scale)..<Int(CGFloat(rows.upperBound) * theme.rowHeight * scale) {
      for pixelX in Int(xs.lowerBound * scale)..<Int(xs.upperBound * scale) {
        let color = try #require(bitmap.colorAt(x: pixelX, y: pixelY))
        if color.redComponent + color.greenComponent + color.blueComponent < 1.5 {
          inked.append(CGFloat(pixelY) / scale - top)
          break
        }
      }
    }
    let first = try #require(inked.first)
    let last = try #require(inked.last)
    return first...(last + 1 / scale)
  }
}

/// Supplies fixed runs and records which blocks a pane asked for.
@MainActor
private final class RecordingHighlights: PaneHighlightProvider {
  private let runs: [Int: [Range<Int>]]
  private(set) var requestedBlocks: [Int] = []

  init(runs: [Int: [Range<Int>]] = [:]) {
    self.runs = runs
  }

  func highlights(forBlock block: Int) -> [Range<Int>] {
    requestedBlocks.append(block)
    return runs[block] ?? []
  }
}
