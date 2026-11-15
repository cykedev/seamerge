import AppKit
import PaneKit
import Testing

/// Checks the search over several panes with the finder of AppKit and its find bar, as the user
/// types into it.
///
/// The finder keeps its search text on the find pasteboard of the system, which every app
/// shares; each test puts back what it held, whether the test passes or not.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct PaneSearchFinderTests {
  @Test func findBarSearchesEveryPaneInTheOrderOfTheSectionsAsTheUserTypes() async throws {
    try await FindPasteboard.preserving {
      let panes = SearchPanes()
      defer { panes.window.close() }
      panes.search.perform(.showFindInterface)
      #expect(panes.search.findBar.isFindBarVisible)
      #expect(panes.search.findBar.barHeight > 0)
      // The search field takes the focus, as in the find bar of a text view.
      let responder = (panes.window.firstResponder as? NSText)?.delegate as? NSView
      #expect(responder?.isDescendant(of: panes.search.findBar) == true)
      try type("needle", into: searchField(of: panes), in: panes.window)
      await waitForMatches(count: 7, of: panes)
      #expect(
        panes.search.matches.map { "\(panes.name(of: $0.pane)) \($0.range)" } == [
          "A 6..<12", "A 13..<19", "Base 0..<6", "Result 0..<6", "A 21..<27", "Base 21..<27",
          "Result 34..<40",
        ])

      // A click in A ends the search as the user types; Find Next goes on from the place of
      // the click, and takes the focus along to the pane of its match.
      panes.window.makeFirstResponder(panes.a.documentView)
      panes.a.documentView.setSelectedRange(NSRange(location: 20, length: 0))
      panes.search.perform(.nextMatch)
      #expect(panes.observer.revealed.last.map { panes.name(of: $0.pane) } == "A")
      #expect(panes.a.documentView.selectedRange() == NSRange(location: 21, length: 6))
      #expect(panes.window.firstResponder === panes.a.documentView)
      panes.search.perform(.nextMatch)
      #expect(panes.observer.revealed.last.map { panes.name(of: $0.pane) } == "Base")
      #expect(panes.base.documentView.selectedRange() == NSRange(location: 21, length: 6))
      #expect(panes.window.firstResponder === panes.base.documentView)

      panes.search.perform(.hideFindInterface)
      #expect(!panes.search.findBar.isFindBarVisible)
      #expect(panes.search.findBar.barHeight == 0)
      #expect(panes.search.matches.isEmpty)
    }
  }

  @Test func replaceAllReplacesInTheResultAloneAsOneStepOfUndoNamedAfterItEvenForOneMatch()
    async throws
  {
    try await FindPasteboard.preserving {
      let panes = SearchPanes()
      defer { panes.window.close() }
      let undoManager = try #require(panes.editor.undoManager)
      undoManager.groupsByEvent = false
      panes.search.scope = .pane(panes.result)
      panes.search.perform(.showReplaceInterface)
      try type("end needle", into: searchField(of: panes), in: panes.window)
      await waitForMatches(count: 1, of: panes)
      let bar = try #require(panes.search.findBar.findBarView)
      let fields = Self.views(in: bar).compactMap { $0 as? NSTextField }
      let replaceField = try #require(fields.first { !($0 is NSSearchField) && $0.isEditable })
      replaceField.stringValue = "pin"
      panes.search.perform(.replaceAll)
      #expect(panes.result.documentView.string == "needle\nneedle\npre needle post\npin")
      #expect(panes.a.documentView.string == SearchPanes.aText)
      #expect(panes.base.documentView.string == SearchPanes.baseText)
      #expect(panes.editor.asked == [PaneEdit(range: 30..<40, text: "pin")])
      #expect(undoManager.undoActionName == "Replace All")
      undoManager.undo()
      #expect(panes.result.documentView.string == SearchPanes.resultText)
      #expect(!undoManager.canUndo)
    }
  }

  /// The search field of the find bar.
  private func searchField(of panes: SearchPanes) throws -> NSSearchField {
    let bar = try #require(panes.search.findBar.findBarView)
    return try #require(Self.views(in: bar).compactMap { $0 as? NSSearchField }.first)
  }

  /// Types `text` into `field` as the user would.
  private func type(_ text: String, into field: NSSearchField, in window: NSWindow) throws {
    window.makeFirstResponder(field)
    let editor = try #require(field.currentEditor() as? NSTextView)
    editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
  }

  /// Returns once the search has found `count` matches; the finder searches on a thread of its
  /// own and hands its matches over on the main queue.
  private func waitForMatches(count: Int, of panes: SearchPanes) async {
    await panes.observer.waitForMatches { panes.search.matches.count == count }
  }

  private static func views(in view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(views(in:))
  }
}

/// The find pasteboard of the system, which the finder writes its search text to.
@MainActor
enum FindPasteboard {
  /// Runs `body` and then puts back what the find pasteboard held before, also if `body` fails,
  /// once what `body` made, its finder among them, is gone.
  static func preserving(_ body: @MainActor () async throws -> Void) async rethrows {
    let restore = save()
    defer { restore() }
    try await body()
  }

  /// Saves what the find pasteboard holds and returns what puts it back.
  private static func save() -> () -> Void {
    let pasteboard = NSPasteboard(name: .find)
    let items = (pasteboard.pasteboardItems ?? []).map { item in
      item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
    }
    return {
      pasteboard.clearContents()
      let restored = items.map { pairs in
        let item = NSPasteboardItem()
        for (type, data) in pairs {
          item.setData(data, forType: type)
        }
        return item
      }
      if !restored.isEmpty {
        pasteboard.writeObjects(restored)
      }
    }
  }
}
