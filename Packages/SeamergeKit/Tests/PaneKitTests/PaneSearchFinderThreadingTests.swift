import AppKit
import PaneKit
import Testing

/// The search while the finder of AppKit reads its text on two threads at once, as it does
/// whenever the user types: one search looks for the first match after the selection, the other
/// for all matches from the top.
///
/// While the search handed the finder its text in parts, two searches at once crashed the app.
///
/// These tests belong to the tests of the finder, which run one after the other: the find
/// pasteboard that they all use is one for the whole system.
extension PaneSearchFinderTests {
  /// Two panes of the same long text, searched in many short sections that take turns between
  /// them, as the blocks of a long comparison do.
  @MainActor
  private final class LongPanes {
    static let rowCount = 40_000
    static let rowsPerSection = 2

    let a = PaneView()
    let b = PaneView()
    let search = PaneSearch()
    let observer = SearchObserver()
    let window: KeyWindow
    let text: NSString

    init() {
      text =
        (0..<Self.rowCount).map { "compute value \($0) entry" }.joined(separator: "\n")
        as NSString
      let lineNumbers = (0..<Int32(Self.rowCount)).map { $0 }
      for pane in [a, b] {
        pane.content = PaneContent(text: text as String, lineNumbers: lineNumbers)
      }
      search.delegate = observer
      let container = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
      for (index, pane) in [a, b].enumerated() {
        pane.frame = CGRect(x: CGFloat(index) * 300, y: 60, width: 300, height: 340)
        container.addSubview(pane)
      }
      search.findBar.frame = CGRect(x: 0, y: 0, width: 600, height: 60)
      container.addSubview(search.findBar)
      window = KeyWindow(
        contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: true)
      window.isReleasedWhenClosed = false
      window.contentView = container
      container.layoutSubtreeIfNeeded()
      search.sections = stride(from: 0, to: Self.rowCount, by: Self.rowsPerSection).flatMap {
        row in
        let rows = row..<min(row + Self.rowsPerSection, Self.rowCount)
        return [
          PaneSearch.Section(pane: a, rows: rows), PaneSearch.Section(pane: b, rows: rows),
        ]
      }
    }

    /// The range of `needle` in the text of each pane.
    func range(of needle: String) -> Range<Int> {
      Range(text.range(of: needle))!
    }
  }

  @Test func searchFromTheMiddleOfAPaneFindsTheMatchesOfEverySectionWhileTheFinderReadsTwice()
    async throws
  {
    try await FindPasteboard.preserving {
      let panes = LongPanes()
      defer { panes.window.close() }
      // The first match is looked for after the selection, far from where the search for all
      // matches begins, so that both read the text at once, far apart.
      panes.a.documentView.setSelectedRange(NSRange(location: panes.text.length / 2, length: 0))
      panes.search.perform(.showFindInterface)
      let field = try findField(of: panes.search)
      for row in [LongPanes.rowCount - 1, 3, LongPanes.rowCount / 2 + 1] {
        let needle = "value \(row) entry"
        let expected = panes.range(of: needle)
        try enter(needle, into: field, in: panes.window)
        await panes.observer.waitForMatches {
          panes.search.matches.map(\.range) == [expected, expected]
        }
        #expect(panes.search.matches.map { $0.pane === panes.a } == [true, false], "\(needle)")
        #expect(panes.search.matches.map(\.range) == [expected, expected], "\(needle)")
      }
      panes.search.perform(.hideFindInterface)
    }
  }
}
