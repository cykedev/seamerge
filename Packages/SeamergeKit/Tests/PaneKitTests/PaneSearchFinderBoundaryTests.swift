import AppKit
import Testing

@testable import PaneKit

/// The search with the finder of AppKit at the ends of lines, sections and panes: a word ends
/// there for Starts With and Full Word, and text of several lines, as text pasted into the
/// search field may hold, finds no match across one, nor does Replace All replace any.
///
/// The find bar searches for the text as the user gives it; it offers no patterns, so that only
/// a text that holds a line break can match one.
///
/// These tests belong to the tests of the finder, which run one after the other: the find
/// pasteboard that they all use is one for the whole system.
extension PaneSearchFinderTests {
  @Test func searchTextOfSeveralLinesFindsNothingAcrossPanesOrSections() async throws {
    try await FindPasteboard.preserving {
      let panes = SearchPanes()
      defer { panes.window.close() }
      panes.search.perform(.showFindInterface)
      let field = try findField(of: panes.search)
      try enter("needle", into: field, in: panes.window)
      await panes.observer.waitForMatches { panes.search.matches.count == 7 }
      // "needle" at the end of the first line of A and at the start of the next in A, at the
      // end of A and at the start of the base, and in the first and third rows of the result.
      for pasted in ["needle\nneedle", "tail\nneedle", "needle\npre"] {
        try enter(pasted, into: field, in: panes.window)
        #expect(field.stringValue == pasted, "the field keeps the line break")
        await panes.observer.waitForMatches {
          panes.search.matchesAreCurrent && panes.search.matches.isEmpty
        }
        #expect(panes.search.matches.isEmpty, "\(pasted)")
        try enter("needle", into: field, in: panes.window)
        await panes.observer.waitForMatches { panes.search.matches.count == 7 }
      }
    }
  }

  @Test func replaceAllOfTextOfSeveralLinesLeavesTheResultAsItIs() async throws {
    try await FindPasteboard.preserving {
      let panes = SearchPanes()
      defer { panes.window.close() }
      let undoManager = try #require(panes.editor.undoManager)
      panes.search.scope = .pane(panes.result)
      panes.search.perform(.showReplaceInterface)
      let field = try findField(of: panes.search)
      try enter("needle\npre", into: field, in: panes.window)
      let bar = try #require(panes.search.findBar.findBarView)
      let fields = subviews(of: bar).compactMap { $0 as? NSTextField }
      let replaceField = try #require(fields.first { !($0 is NSSearchField) && $0.isEditable })
      replaceField.stringValue = "x"
      let pasteboard = NSPasteboard(name: .find)
      pasteboard.clearContents()
      pasteboard.setString(field.stringValue, forType: .string)
      panes.search.perform(.replaceAll)
      #expect(panes.result.documentView.string == SearchPanes.resultText)
      #expect(panes.editor.asked.isEmpty)
      #expect(!undoManager.canUndo)
    }
  }

  @Test func startsWithAndFullWordMatchAtTheStartAndEndOfEverySection() async {
    await FindPasteboard.preserving {
      let panes = SearchPanes()
      defer { panes.window.close() }
      let everyNeedle = [
        "A 6..<12", "A 13..<19", "Base 0..<6", "Result 0..<6", "A 21..<27", "Base 21..<27",
        "Result 34..<40",
      ]
      // Each needle in the base and the result starts its section, right after one of A or the
      // base; "tail" ends the last line of A, right before one of the base.
      let searches: [(String, NSTextFinder.MatchingType, [String])] = [
        ("needle", .startsWith, everyNeedle),
        ("needle", .fullWord, everyNeedle),
        ("tail", .fullWord, ["A 28..<32"]),
      ]
      for (needle, matching, expected) in searches {
        // How the find bar matches words is a setting that every find bar of the system takes
        // from the find pasteboard as it opens.
        let pasteboard = NSPasteboard(name: .find)
        pasteboard.clearContents()
        pasteboard.setString(needle, forType: .string)
        pasteboard.setPropertyList(
          [
            NSPasteboard.PasteboardType.TextFinderOptionKey.textFinderMatchingTypeKey.rawValue:
              matching.rawValue
          ],
          forType: .findPanelSearchOptions)
        panes.search.perform(.showFindInterface)
        let places = { panes.search.matches.map { "\(panes.name(of: $0.pane)) \($0.range)" } }
        await panes.observer.waitForMatches { places() == expected }
        #expect(places() == expected, "\(needle) \(matching.rawValue)")
        panes.search.perform(.hideFindInterface)
      }
    }
  }
}
