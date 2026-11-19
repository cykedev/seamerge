import AppKit
import Testing

@testable import PaneKit

/// Content prepared away from the main actor: the pane shows it as it shows the same content
/// given as it is, whatever characters its text holds.
@MainActor
@Suite struct PreparedContentTests {
  private static let text = "let greeting = \"Grüße 😀\"\n\t\t\t\t\t\t\t\t\tdeep\nlast\n"

  private func content(_ text: String = text) -> PaneContent {
    let rows = text.split(separator: "\n", omittingEmptySubsequences: false).count
    return PaneContent(
      text: text, lineNumbers: (0..<Int32(rows)).map(\.self),
      blocks: [PaneBlock(rows: 1..<2, style: .tinted(.b), marker: .changed)])
  }

  @Test func preparedContentShowsAsTheSameContentGivenAsItIs() {
    let given = PaneView()
    given.setContent(content(), collapsedRuns: [])
    let prepared = PaneView()
    prepared.setContent(
      PreparedPaneContent(preparing: content(), tabWidth: prepared.theme.tabWidth),
      collapsedRuns: [CollapsedRun(rows: 2..<4)])
    given.collapsedRuns = [CollapsedRun(rows: 2..<4)]

    #expect(prepared.textView.string == given.textView.string)
    #expect(prepared.content.blocks == given.content.blocks)
    #expect(prepared.textView.grid.rowCount == given.textView.grid.rowCount)
    #expect(prepared.textView.grid.widestRowColumns == given.textView.grid.widestRowColumns)
    #expect(prepared.collapsedRuns == given.collapsedRuns)
  }

  /// A text that starts with a byte order mark keeps it as a character, which Foundation
  /// would drop on the way from UTF-8; the pane holds the same characters as the text either
  /// way, so that its rows and every range in them are where they are.
  @Test(arguments: ["\u{FEFF}first\nsecond\n", "first\u{FEFF}\nsecond\n"])
  func preparedContentKeepsAByteOrderMarkInItsText(text: String) {
    let given = PaneView()
    given.setContent(content(text), collapsedRuns: [])
    let prepared = PaneView()
    prepared.setContent(
      PreparedPaneContent(preparing: content(text), tabWidth: prepared.theme.tabWidth),
      collapsedRuns: [])

    #expect(prepared.textView.string.utf16.count == text.utf16.count)
    #expect(prepared.textView.string == given.textView.string)
    #expect(prepared.textView.grid.textLength == text.utf16.count)
  }

  @Test func contentPreparedForAnotherTabWidthFindsItsRowsAnew() {
    let pane = PaneView()
    let tabWidth = pane.theme.tabWidth
    pane.setContent(
      PreparedPaneContent(preparing: content(), tabWidth: tabWidth * 2), collapsedRuns: [])
    #expect(
      pane.textView.grid.widestRowColumns
        == RowGrid(text: Self.text, tabWidth: tabWidth).widestRowColumns)
  }

  @Test func preparedContentOfTheSameTextKeepsTheSelection() {
    let pane = PaneView()
    pane.setContent(content(), collapsedRuns: [])
    pane.textView.setSelectedRange(NSRange(location: 4, length: 8))
    pane.setContent(
      PreparedPaneContent(preparing: content(), tabWidth: pane.theme.tabWidth), collapsedRuns: [])
    #expect(pane.textView.selectedRange() == NSRange(location: 4, length: 8))
  }
}
