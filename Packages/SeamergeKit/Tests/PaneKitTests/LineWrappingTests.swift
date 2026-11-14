import AppKit
import Testing

@testable import PaneKit

/// Checks that rows wrap as TextKit wraps them: the screen lines that the pane counts for each
/// row before it lays the row out are the lines TextKit lays out, at every width.
@MainActor
@Suite struct LineWrappingTests {
  @Test(arguments: [260, 297, 333, 420, 700] as [CGFloat])
  func screenLinesOfEachRowAreTheLinesTextKitLaysOut(width: CGFloat) throws {
    let pane = PaneView()
    pane.wrapsLines = true
    pane.content = PaneContent(
      text: Self.trickyLines.joined(separator: "\n"),
      lineNumbers: Self.trickyLines.indices.map(Int32.init))
    let window = Rendering.host(pane, size: CGSize(width: width, height: 2_000))
    defer { window.close() }
    let textView = pane.textView
    let manager = try #require(textView.textLayoutManager)
    manager.ensureLayout(for: manager.documentRange)
    #expect(pane.displayRows.lineCount > Self.trickyLines.count + 2, "some rows wrap")
    for row in Self.trickyLines.indices {
      let fragment = try #require(fragment(ofRow: row, in: textView))
      let laidOut = fragment.textLineFragments.count
      let counted = pane.displayRows.lines(ofRows: row..<row + 1).count
      #expect(counted == laidOut, "width \(width), row \(row): \(Self.trickyLines[row])")
    }
  }

  @Test func linesAfterTheFirstGoOnTwoColumnsBeyondTheIndentationOfTheRow() throws {
    let pane = PaneView()
    pane.wrapsLines = true
    let rows = [
      "    four spaces and then enough words to wrap onto a second line for sure",
      "\tone tab and then enough words to wrap onto a second line for sure, also",
      String(repeating: " ", count: 30)
        + "very deep indentation that the lines below follow only so far",
    ]
    pane.content = PaneContent(
      text: rows.joined(separator: "\n"), lineNumbers: rows.indices.map(Int32.init))
    let window = Rendering.host(pane, size: CGSize(width: 420, height: 600))
    defer { window.close() }
    let manager = try #require(pane.textView.textLayoutManager)
    manager.ensureLayout(for: manager.documentRange)
    let width = pane.theme.characterWidth
    for (row, columns) in [(0, 6), (1, 6), (2, 18)] {
      let fragment = try #require(fragment(ofRow: row, in: pane.textView))
      let lines = fragment.textLineFragments
      try #require(lines.count > 1, "row \(row) wraps")
      let start =
        lines[1].typographicBounds.minX
        + lines[1].locationForCharacter(at: lines[1].characterRange.lowerBound).x
      #expect(abs(start - CGFloat(columns) * width) < 0.5, "row \(row)")
      #expect(pane.displayRows.lines(ofRows: row..<row + 1).count == lines.count, "row \(row)")
    }
  }

  @Test func rowsLaidOutBeforeLinesWrappedWrapOnceTheyComeIntoView() throws {
    let long = String(repeating: "words that run on ", count: 10)
    let lines = (0..<300).map { $0 % 10 == 0 ? long : "short \($0)" }
    let pane = PaneView()
    pane.content = PaneContent(
      text: lines.joined(separator: "\n"), lineNumbers: lines.indices.map(Int32.init))
    let window = Rendering.host(pane, size: CGSize(width: 420, height: 300))
    defer { window.close() }
    let textView = pane.textView
    let manager = try #require(textView.textLayoutManager)
    manager.textViewportLayoutController.layoutViewport()
    textView.scroll(CGPoint(x: 0, y: textView.frame.height))
    window.contentView?.layoutSubtreeIfNeeded()
    manager.textViewportLayoutController.layoutViewport()

    pane.wrapsLines = true
    window.contentView?.layoutSubtreeIfNeeded()
    textView.scroll(.zero)
    window.contentView?.layoutSubtreeIfNeeded()
    manager.textViewportLayoutController.layoutViewport()

    for row in stride(from: 0, to: 20, by: 10) {
      let fragment = try #require(fragment(ofRow: row, in: textView))
      #expect(fragment.textLineFragments.count > 1, "row \(row)")
      #expect(
        fragment.textLineFragments.count == pane.displayRows.lines(ofRows: row..<row + 1).count,
        "row \(row)")
    }
  }

  @Test func rowsTakeOneLineEachWhileLinesDoNotWrap() {
    let pane = PaneView()
    pane.content = PaneContent(
      text: Self.trickyLines.joined(separator: "\n"),
      lineNumbers: Self.trickyLines.indices.map(Int32.init))
    let window = Rendering.host(pane, size: CGSize(width: 260, height: 600))
    defer { window.close() }
    #expect(pane.displayRows.lineCount == Self.trickyLines.count)
  }

  private func fragment(ofRow row: Int, in textView: PaneTextView) -> NSTextLayoutFragment? {
    guard let manager = textView.textLayoutManager else { return nil }
    let offset = textView.grid.offsets(ofRow: row).lowerBound
    guard let location = manager.location(manager.documentRange.location, offsetBy: offset)
    else { return nil }
    return manager.textLayoutFragment(for: location)
  }

  /// Lines that break in different ways: at spaces, at punctuation, within words longer than a
  /// line, with tabs, wide characters, emoji and combining marks.
  static let trickyLines = [
    "short",
    String(repeating: "word ", count: 40),
    String(repeating: "x", count: 150),
    "let url = \"https://example.com/a/very/long/path/that/goes/on/and/on/index.html?query=value&other=1\"",
    "\tif (alpha && beta) || (gamma != delta) { return compute(alpha, beta, gamma, delta, epsilon) }",
    "\t\t\tdeeply.nested.call(with: arguments, and: more, plus: evenMore, until: theLineIsLong)",
    "Ümlaute und Grüße: äöü ÄÖÜ ß, dazu eine lange Erklärung, die über den Rand hinaus läuft.",
    "// 日本語のコメントがとても長くなって画面の幅を超えてしまう場合の折り返しを確認します。",
    "SHIPPED(\"Versandt 📦\"), DELIVERED(\"Zugestellt 🎉\"), RETURNED(\"Zurück ↩︎\"), LOST(\"Verloren\")",
    "a-b-c-d-e-f-g-h-i-j-k-l-m-n-o-p-q-r-s-t-u-v-w-x-y-z-a-b-c-d-e-f-g-h-i-j-k-l-m-n-o-p-q-r-s-t",
    "trailing spaces at the end of a line that is long enough to wrap somewhere          ",
    "",
    "e\u{301}e\u{301}e\u{301} combining marks e\u{301}e\u{301} and more words to make it wrap ok",
    "last",
  ]
}
