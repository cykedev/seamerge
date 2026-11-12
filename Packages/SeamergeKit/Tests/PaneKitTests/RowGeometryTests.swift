import AppKit
import PaneKit
import Synchronization
import Testing

/// Checks that rows lie on the grid, however large the file and whatever it contains, and that
/// the text view never falls back to TextKit 1.
@MainActor
@Suite struct RowGeometryTests {
  @Test func rowsLieAtTheirRowTimesTheRowHeightInOneHundredThousandRows() throws {
    let theme = Theme()
    let (content, rowStarts) = Self.largeContent()
    let pane = PaneView(theme: theme)
    pane.content = content
    let window = Rendering.host(
      pane, size: CGSize(width: 800, height: 600), appearance: Look.all[0].appearance)
    defer { window.close() }
    let textView = pane.documentView
    #expect(textView.frame.height == CGFloat(Self.rowCount) * theme.rowHeight)
    let visibleRows = 24
    for target in Self.scrollTargets {
      textView.scroll(CGPoint(x: 0, y: CGFloat(target) * theme.rowHeight))
      // Scrolling stops at the end of the text.
      let firstRow = Int(textView.visibleRect.minY / theme.rowHeight)
      let bitmap = try Rendering.bitmap(of: pane)
      let textStart = pane.bounds.width - textView.visibleRect.width
      // Filler rows are empty and every other row has text, so a row drawn off the grid shows
      // as ink where a filler row should be, or as none where text should be.
      for row in firstRow..<min(firstRow + visibleRows, Self.rowCount) {
        let top = CGFloat(row - firstRow) * theme.rowHeight
        let hasInk = try Self.hasInk(
          in: bitmap, xs: textStart + 40..<textStart + 300, ys: top + 1..<top + theme.rowHeight - 1)
        #expect(hasInk == (content.lineNumbers[row] >= 0), "row \(row)")
      }
      // A click in the middle of a row lands in that row.
      let row = firstRow + 2
      let index = textView.characterIndexForInsertion(
        at: CGPoint(x: 100, y: (CGFloat(row) + 0.5) * theme.rowHeight))
      #expect((rowStarts[row]...rowStarts[row + 1] - 1).contains(index), "click in row \(row)")
    }
  }

  @Test func textViewStaysOnTextKit2() throws {
    let switched = Mutex(false)
    let observer = NotificationCenter.default.addObserver(
      forName: NSTextView.willSwitchToNSLayoutManagerNotification, object: nil, queue: nil
    ) { _ in
      switched.withLock { $0 = true }
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    let pane = PaneView()
    pane.content = SampleMerge.transcoder.content(of: .a)
    pane.currentBlock = SampleMerge.openConflictBlock
    let window = Rendering.host(pane, size: CGSize(width: 600, height: 400))
    defer { window.close() }
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: 10, length: 200))
    textView.copy(nil)
    textView.scroll(CGPoint(x: 80, y: 120))
    _ = try Rendering.bitmap(of: pane)
    #expect(textView.textLayoutManager != nil)
    #expect(!switched.withLock { $0 })
  }

  @Test func paneIsWideEnoughForItsWidestLineBeforeTextKitLaysItOut() throws {
    let theme = Theme()
    let widest = String(repeating: "漢字かな😀\t", count: 30)
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(text: "short\n\(widest)\nshort", lineNumbers: [0, 1, 2])
    let window = Rendering.host(pane, size: CGSize(width: 400, height: 200))
    defer { window.close() }
    let measured = (widest as NSString).size(withAttributes: [.font: theme.font]).width
    #expect(pane.documentView.frame.width >= measured)
  }

  private static let rowCount = 100_000

  /// The rows to scroll to the top of the pane: the start, rows with emoji and with CJK
  /// characters far down, and the end.
  private static let scrollTargets = [0, 3_990, 4_490, 50_000, 77_777, 99_976]

  /// Whether `bitmap` has a dark pixel within `xs` and `ys`, in the view's coordinates.
  private static func hasInk(
    in bitmap: NSBitmapImageRep, xs: Range<CGFloat>, ys: Range<CGFloat>
  ) throws -> Bool {
    let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
    for pixelY in Int(ys.lowerBound * scale)..<Int(ys.upperBound * scale) {
      for pixelX in Int(xs.lowerBound * scale)..<Int(xs.upperBound * scale) {
        let color = try #require(bitmap.colorAt(x: pixelX, y: pixelY))
        if color.redComponent + color.greenComponent + color.blueComponent < 1.5 {
          return true
        }
      }
    }
    return false
  }

  /// 100 000 rows of code-like text with an emoji every 1000 rows, CJK characters every 1000
  /// rows offset by 500, a filler row every seven rows and an empty last row.
  private static func largeContent() -> (PaneContent, rowStarts: [Int]) {
    var rows: [String] = []
    var lineNumbers: [Int32] = []
    var line: Int32 = 0
    for row in 0..<rowCount {
      if row % 7 == 6 || row == rowCount - 1 {
        rows.append("")
        lineNumbers.append(-1)
        continue
      }
      var text = "    let value\(row) = compute(\(row), scale: 0.5) // row \(row)"
      if row % 1000 == 0 { text += " 😀👩‍💻" }
      if row % 1000 == 500 { text += " 漢字かなカナ" }
      rows.append(text)
      lineNumbers.append(line)
      line += 1
    }
    var rowStarts: [Int] = []
    var offset = 0
    for row in rows {
      rowStarts.append(offset)
      offset += row.utf16.count + 1
    }
    return (
      PaneContent(
        text: rows.joined(separator: "\n"), lineNumbers: lineNumbers,
        blocks: [PaneBlock(rows: 4_000..<4_010, style: .tinted(.a), marker: .changed)]),
      rowStarts
    )
  }
}
