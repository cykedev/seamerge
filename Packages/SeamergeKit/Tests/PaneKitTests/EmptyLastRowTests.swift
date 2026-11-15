import AppKit
import Testing

@testable import PaneKit

/// The insertion point on an empty last row stands on that row, also where a neighbor wraps the
/// row before it into more screen lines than the pane's own text takes.
@MainActor
@Suite struct EmptyLastRowTests {
  @Test func insertionPointOnAnEmptyLastRowStandsOnItsRow() throws {
    let long = "let message = " + String(repeating: "\"words that run on\" + ", count: 8) + "\"\""
    let texts = [["first", "short", ""], ["first", long, "last"]]
    let container = RowAlignmentTests.SideBySide()
    let alignment = RowAlignment()
    let panes = texts.map { lines in
      let pane = PaneView()
      pane.wrapsLines = true
      pane.content = PaneContent(
        text: lines.joined(separator: "\n"), lineNumbers: lines.indices.map(Int32.init))
      container.addSubview(pane)
      alignment.add(pane)
      return pane
    }
    container.alignment = alignment
    let window = Rendering.host(container, size: CGSize(width: 900, height: 600), isKey: true)
    defer { window.close() }
    let pane = panes[0]
    let recorder = EditRecorder()
    pane.editingDelegate = recorder
    defer { withExtendedLifetime(recorder) {} }
    let textView = pane.textView
    try #require(pane.displayRows.lines(ofRows: 1..<2).count > 1, "the neighbor wraps row 1")
    window.makeFirstResponder(textView)
    let end = (textView.string as NSString).length
    textView.setSelectedRange(NSRange(location: end, length: 0))
    textView.displayIfNeeded()

    let row = pane.verticalSpan(ofRows: 2..<3)
    let indicator = try #require(
      textView.subviews.compactMap { $0 as? NSTextInsertionIndicator }.first)
    var actualRange = NSRange()
    let onScreen = textView.firstRect(
      forCharacterRange: NSRange(location: end, length: 0), actualRange: &actualRange)
    let rect = textView.convert(window.convertFromScreen(onScreen), from: nil)
    #expect(row.contains(indicator.frame.midY))
    #expect(row.contains(rect.midY))
  }
}
