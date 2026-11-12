import AppKit
import PaneKit
import Testing

/// Checks that what the system places by the text's geometry lands on the text as the pane draws
/// it, raised to the middle of its row: the insertion point, the rectangle that input methods put
/// their candidates next to, and the frame of VoiceOver's cursor.
@MainActor
@Suite struct TextGeometryTests {
  @Test func insertionPointCoversTheTextOfItsRow() throws {
    let (pane, window, _) = EditingTests.editablePane(text: Self.text)
    defer { window.close() }
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: 14, length: 0))
    textView.displayIfNeeded()
    let indicator = try #require(
      textView.subviews.compactMap { $0 as? NSTextInsertionIndicator }.first)
    let ink = try Self.ink(of: pane, inRow: 1, xs: 20..<120)
    Self.expect(ink, centeredIn: indicator.frame)
  }

  @Test func rectangleForInputMethodsCoversTheDrawnCharacters() throws {
    let (pane, window, _) = EditingTests.editablePane(text: Self.text)
    defer { window.close() }
    let textView = pane.documentView
    var actualRange = NSRange()
    let onScreen = textView.firstRect(
      forCharacterRange: NSRange(location: 14, length: 4), actualRange: &actualRange)
    let rect = textView.convert(window.convertFromScreen(onScreen), from: nil)
    let ink = try Self.ink(of: pane, inRow: 1, xs: rect.minX..<rect.maxX)
    Self.expect(ink, centeredIn: rect)
  }

  @Test func frameOfVoiceOversCursorCoversTheDrawnCharacters() throws {
    let (pane, window, _) = EditingTests.editablePane(text: Self.text)
    defer { window.close() }
    let textView = pane.documentView
    let onScreen = textView.accessibilityFrame(for: NSRange(location: 14, length: 4))
    let rect = textView.convert(window.convertFromScreen(onScreen), from: nil)
    let ink = try Self.ink(of: pane, inRow: 1, xs: rect.minX..<rect.maxX)
    Self.expect(ink, centeredIn: rect)
  }

  /// Expects `ink` to lie within `rect` with about as much room above as below, as text raised to
  /// the middle of its row does; text where TextKit puts it would leave three times as much room
  /// above as below.
  static func expect(
    _ ink: ClosedRange<CGFloat>, centeredIn rect: CGRect,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let above = ink.lowerBound - rect.minY
    let below = rect.maxY - ink.upperBound
    #expect(above >= 0 && below >= 0, "ink \(ink) outside \(rect)", sourceLocation: sourceLocation)
    #expect(
      abs(above - below) <= 2, "\(above) above, \(below) below", sourceLocation: sourceLocation)
  }

  /// Text with letters that reach above and below the line in its second row.
  static let text = "first line\nHgjy Ågjy line\nthird line"

  /// The vertical extent of the ink that the text view draws within `xs` of `row`, in its own
  /// coordinates.
  static func ink(of pane: PaneView, inRow row: Int, xs: Range<CGFloat>) throws
    -> ClosedRange<CGFloat>
  {
    let textView = pane.documentView
    let window = try #require(textView.window)
    window.makeFirstResponder(nil)
    defer { window.makeFirstResponder(textView) }
    let bitmap = try Rendering.bitmap(of: textView)
    let rowHeight = pane.theme.rowHeight
    var rows: [CGFloat] = []
    for y in stride(from: CGFloat(row) * rowHeight, to: CGFloat(row + 1) * rowHeight, by: 0.5) {
      for x in stride(from: xs.lowerBound, to: xs.upperBound, by: 0.5) {
        if try Rendering.color(in: bitmap, at: CGPoint(x: x, y: y)).brightnessComponent < 0.6 {
          rows.append(y)
          break
        }
      }
    }
    let top = try #require(rows.first)
    let bottom = try #require(rows.last)
    // Capitals, ascenders and descenders reach over most of the font's height.
    try #require(bottom - top > pane.theme.font.pointSize * 0.8)
    return top...bottom + 0.5
  }
}
