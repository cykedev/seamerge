import AppKit
import Testing

@testable import PaneKit

/// Checks that no match of the search reaches across the end of a line, from one section into
/// the next or from one pane into the next, also when the search text holds a line break, as
/// text pasted into the search field may: such a match is shown in no pane, selects nothing
/// there and is never replaced.
///
/// These tests ask the search as the finder would, without the finder itself; those with the
/// finder are among the tests of the finder.
@MainActor
@Suite struct PaneSearchBoundaryTests {
  /// The search text as the finder reads it.
  private func searchString(of panes: SearchPanes) -> NSString {
    panes.search.string as NSString
  }

  @Test func lineFeedStandsBetweenEveryTwoPiecesOfOnePaneOrOfTwo() {
    let panes = SearchPanes()
    defer { panes.window.close() }
    #expect(
      panes.search.string
        == "alpha needle\nneedle\nneedle\nneedle\nneedle tail\nneedle\npre \n post\nend needle")
  }

  @Test func matchFromOnePaneIntoTheNextIsShownNowhereAndSelectsAfterItself() throws {
    let panes = SearchPanes()
    defer { panes.window.close() }
    // The last line of A, "needle tail", and the next line, "needle" in the base.
    let across = searchString(of: panes).range(of: "tail\nneedle")
    try #require(across.location != NSNotFound)
    var stretch = NSRange()
    #expect(
      panes.search.contentView(at: across.location, effectiveCharacterRange: &stretch)
        === panes.a.documentView)
    #expect(NSMaxRange(across) > NSMaxRange(stretch), "the match ends in the base")

    panes.search.scrollRangeToVisible(across)
    #expect(panes.observer.revealed.isEmpty)
    #expect(panes.search.rects(forCharacterRange: across) == nil)
    panes.search.selectedRanges = [NSValue(range: across)]
    // Find Next goes on after the match, at the end of "needle" in the base.
    #expect(panes.base.documentView.selectedRange() == NSRange(location: 27, length: 0))
  }

  @Test func matchFromOneSectionIntoTheNextOfThePaneIsNeverReplaced() throws {
    let panes = SearchPanes()
    defer { panes.window.close() }
    panes.search.scope = .pane(panes.result)
    // The first row of the result, "needle", and the third, "pre ", in the next section.
    #expect(panes.search.string == "needle\npre \n post\nend needle")
    let across = NSRange(location: 0, length: 10)
    let needle = NSRange(location: 22, length: 6)
    #expect(
      !panes.search.shouldReplaceCharacters(inRanges: [NSValue(range: across)], with: ["x"]))
    #expect(
      panes.search.shouldReplaceCharacters(
        inRanges: [NSValue(range: across), NSValue(range: needle)], with: ["x", "pin"]))
    panes.search.replaceCharacters(in: needle, with: "pin")
    panes.search.replaceCharacters(in: across, with: "x")
    panes.search.didReplaceCharacters()
    #expect(panes.result.documentView.string == "needle\nneedle\npre needle post\nend pin")
  }
}
