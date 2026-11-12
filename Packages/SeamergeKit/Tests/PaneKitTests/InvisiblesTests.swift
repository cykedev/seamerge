import AppKit
import PaneKit
import Testing

/// Checks the symbols for spaces, tabs and line endings: hidden until asked for, then in the
/// cell of their character, one symbol for each kind of line ending.
@MainActor
@Suite struct InvisiblesTests {
  private let theme = Theme()
  private let appearance = Look.all[0].appearance

  @Test func spacesAndTabsShowOnlyWhenAskedFor() throws {
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(text: "a b\tc", lineNumbers: [0])
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 60), appearance: appearance)
    defer { window.close() }
    let space = cell(column: 1, in: pane)
    let tab = cell(column: 3, in: pane)
    var bitmap = try Rendering.bitmap(of: pane)
    #expect(try !Self.hasInk(in: bitmap, rect: space))
    #expect(try !Self.hasInk(in: bitmap, rect: tab))
    pane.showsInvisibles = true
    bitmap = try Rendering.bitmap(of: pane)
    #expect(try Self.hasInk(in: bitmap, rect: space))
    #expect(try Self.hasInk(in: bitmap, rect: tab))
    pane.showsInvisibles = false
    bitmap = try Rendering.bitmap(of: pane)
    #expect(try !Self.hasInk(in: bitmap, rect: space))
  }

  @Test func switchingInvisiblesHasEveryFragmentInViewDrawnAgain() throws {
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(text: "a b\nc d\ne f", lineNumbers: [0, 1, 2])
    let window = Rendering.host(
      pane, size: CGSize(width: 300, height: 100), appearance: appearance, isKey: true)
    defer { window.close() }
    window.orderFrontRegardless()
    pane.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    // TextKit draws each fragment into a view of its own and keeps the drawing in its layer,
    // which a window on screen shows until the layer is marked as needing display.
    let views = Self.descendants(of: pane.documentView)
    for view in views {
      view.layer?.displayIfNeeded()
    }
    try #require(views.count > 2)
    pane.showsInvisibles = true
    let stale = views.filter { !($0.layer?.needsDisplay() ?? true) }
    #expect(stale.isEmpty, "\(stale.map { type(of: $0) })")
  }

  /// Every view within `view`, at any depth.
  private static func descendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants(of: $0) }
  }

  @Test func everyLineEndingHasASymbolOfItsOwn() throws {
    let endings: [LineEnding] = [.lineFeed, .carriageReturnLineFeed, .carriageReturn, .none]
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(
      text: "x\nx\nx\nx", lineNumbers: [0, 1, 2, 3], lineEndings: endings)
    pane.showsInvisibles = true
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 100), appearance: appearance)
    defer { window.close() }
    let bitmap = try Rendering.bitmap(of: pane)
    var inks: [[Bool]] = []
    for row in endings.indices {
      let rect = cell(column: 1, in: pane, row: row, width: 2)
      inks.append(try Self.inkPattern(in: bitmap, rect: rect))
    }
    #expect(inks[3].allSatisfy { !$0 }, "a line without an ending shows nothing")
    for first in 0..<3 {
      #expect(inks[first].contains(true), "\(endings[first]) shows a symbol")
      for second in first + 1..<3 {
        #expect(inks[first] != inks[second], "\(endings[first]) and \(endings[second]) differ")
      }
    }
  }

  @Test func fillerRowsShowNoLineEnding() throws {
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(text: "x\n\nx", lineNumbers: [0, -1, 1])
    pane.showsInvisibles = true
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 100), appearance: appearance)
    defer { window.close() }
    let bitmap = try Rendering.bitmap(of: pane)
    #expect(try Self.hasInk(in: bitmap, rect: cell(column: 1, in: pane, row: 0)))
    #expect(try !Self.hasInk(in: bitmap, rect: cell(column: 0, in: pane, row: 1, width: 3)))
  }

  /// The cells of `width` characters from `column` of `row`, in the pane's coordinates.
  private func cell(column: Int, in pane: PaneView, row: Int = 0, width: Int = 1) -> CGRect {
    let characterWidth = ("0" as NSString).size(withAttributes: [.font: theme.font]).width
    let textStart = pane.bounds.width - pane.documentView.visibleRect.width + 12
    return CGRect(
      x: textStart + CGFloat(column) * characterWidth + 1,
      y: CGFloat(row) * theme.rowHeight + 2, width: CGFloat(width) * characterWidth - 2,
      height: theme.rowHeight - 4)
  }

  private static func hasInk(in bitmap: NSBitmapImageRep, rect: CGRect) throws -> Bool {
    try inkPattern(in: bitmap, rect: rect).contains(true)
  }

  /// Whether each pixel within `rect` is darker than the background.
  private static func inkPattern(in bitmap: NSBitmapImageRep, rect: CGRect) throws -> [Bool] {
    let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
    var pattern: [Bool] = []
    for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
      for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
        let color = try #require(bitmap.colorAt(x: x, y: y))
        pattern.append(color.redComponent + color.greenComponent + color.blueComponent < 2.7)
      }
    }
    return pattern
  }
}
