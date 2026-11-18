import AppKit
import Testing

@testable import PaneKit

/// The matches of the finder while they are placed in the panes away from the main actor: a
/// change of the text meanwhile drops them, since their ranges refer to the text as it was.
///
/// These tests belong to the tests of the finder, which run one after the other: the find
/// pasteboard that they all use is one for the whole system.
extension PaneSearchFinderTests {
  @Test func matchesPlacedWhileTheTextChangesNeverShow() async throws {
    try await FindPasteboard.preserving {
      let rowCount = 20_000
      let pane = PaneView()
      pane.content = PaneContent(
        text: (0..<rowCount).map { "needle \($0)" }.joined(separator: "\n"),
        lineNumbers: (0..<Int32(rowCount)).map { $0 })
      let search = PaneSearch()
      search.sections = [PaneSearch.Section(pane: pane, rows: 0..<rowCount)]
      let container = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
      pane.frame = CGRect(x: 0, y: 60, width: 400, height: 340)
      container.addSubview(pane)
      search.findBar.frame = CGRect(x: 0, y: 0, width: 400, height: 60)
      container.addSubview(search.findBar)
      let window = KeyWindow(
        contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: true)
      window.isReleasedWhenClosed = false
      window.contentView = container
      defer { window.close() }
      search.perform(.showFindInterface)
      try enter("needle", into: findField(of: search), in: window)

      // The finder hands its matches over on the main queue; placing twenty thousand of them
      // takes longer than this test takes to look.
      while search.matchesInPreparation == nil, !Task.isCancelled {
        await Task.yield()
      }
      let placing = try #require(search.matchesInPreparation)
      _ = pane.carryOut([PaneEdit(range: 0..<0, text: "x")])
      await placing.value

      #expect(search.matchCount == 0)
      #expect(!search.matchesAreCurrent)
      #expect(pane.textView.searchMatches.isEmpty)
    }
  }

  @Test func moreMatchesThanAreReadAtOnceAllShowInTheirOrder() async throws {
    try await FindPasteboard.preserving {
      // Ten matches a row, a few rows more than one part of the finder's array holds.
      let rowCount = PaneSearch.matchesReadAtOnce / 10 + 7
      let pane = PaneView()
      pane.content = PaneContent(
        text: Array(repeating: "x x x x x x x x x x", count: rowCount).joined(separator: "\n"),
        lineNumbers: (0..<Int32(rowCount)).map { $0 })
      let search = PaneSearch()
      let observer = SearchObserver()
      search.delegate = observer
      search.sections = [PaneSearch.Section(pane: pane, rows: 0..<rowCount)]
      let container = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
      pane.frame = CGRect(x: 0, y: 60, width: 400, height: 340)
      container.addSubview(pane)
      search.findBar.frame = CGRect(x: 0, y: 0, width: 400, height: 60)
      container.addSubview(search.findBar)
      let window = KeyWindow(
        contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: true)
      window.isReleasedWhenClosed = false
      window.contentView = container
      defer { window.close() }
      search.perform(.showFindInterface)
      try enter("x", into: findField(of: search), in: window)

      await observer.waitForMatches { search.matchCount == rowCount * 10 }

      #expect(search.matchCount == rowCount * 10)
      let ranges = pane.textView.searchMatches
      #expect(ranges.count == rowCount * 10)
      // Each row of 19 characters and its line feed holds a match at every even column.
      #expect(
        ranges.enumerated().allSatisfy { index, range in
          range == (index / 10 * 20 + index % 10 * 2)..<(index / 10 * 20 + index % 10 * 2 + 1)
        })
      #expect(search.matchRows(in: pane) == IndexSet(integersIn: 0..<rowCount))
    }
  }
}
