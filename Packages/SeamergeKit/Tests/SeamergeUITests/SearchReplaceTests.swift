import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Replacing in the result: the edits pass through the result document
/// as typing does, never touch a preview, and each replacement is one step of undo with its
/// name, after which typing starts a step of its own.
///
/// The finder keeps its search text on the find pasteboard of the system, which every app
/// shares; each test puts back what it held, whether the test passes or not.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SearchReplaceTests {
  /// The window of the merge of nine blocks with an undo manager that groups nothing by itself,
  /// so that only the window can join edits into one step, and the find bar open for replacing
  /// in the result.
  private static func window() async throws -> (SessionWindowController, SearchDriver) {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let controller = try Windows.controller(
      for: try await EditingFixture.nineBlocks(), undoManager: undoManager)
    let driver = SearchDriver(controller)
    let search = controller.presentation.search
    search.scope = .pane(try #require(controller.layout.resultPane))
    search.perform(.showReplaceInterface)
    return (controller, driver)
  }

  /// Searches for `needle`, waits for `count` matches and puts `replacement` into the field for
  /// replacing.
  private static func prepare(
    _ driver: SearchDriver, replacing needle: String, matches count: Int, with replacement: String
  ) async throws {
    try driver.type(needle)
    await driver.waitForMatches(count: count)
    try driver.typeReplacement(replacement)
  }

  @Test func replaceAllIsOneStepOfUndoNamedAfterItAndNeverTouchesAPreview() async throws {
    try await FindPasteboard.preserving {
      let (controller, driver) = try await Self.window()
      let window = try #require(controller.window)
      defer { window.close() }
      let undoManager = controller.sessionUndoManager
      let sources = Windows.panes(of: controller).dropLast().map(\.documentView.string)

      // "B" stands in block 5, taken from B, and in the preview of the conflict of block 3.
      try await Self.prepare(driver, replacing: "B", matches: 1, with: "Q")
      driver.search.perform(.replaceAll)
      var texts = try controller.segmentTexts
      #expect(texts[3] == "A3\nB3\n")
      #expect(texts[5] == "Q5\n")
      #expect(try controller.segmentStates[3] == .open)
      #expect(undoManager.undoActionName == "Replace All")
      // The finder searches the changed text anew; only the preview holds "B" now.
      await driver.waitForMatches(count: 0)

      try await Self.prepare(driver, replacing: "u", matches: 5, with: "v")
      driver.search.perform(.replaceAll)
      let replaced = try controller.presentation.mergeResult.text
      #expect(
        replaced == "v0\nA1\nv2\nA3\nB3\nv4\nQ5\nv6\n\(EditingFixture.removalNote)\nY7\nv8\n")
      #expect(try controller.segmentStates[3] == .open)
      #expect(Windows.panes(of: controller).dropLast().map(\.documentView.string) == sources)
      try controller.checkResultIsShownAsModelled()
      #expect(undoManager.undoActionName == "Replace All")
      #expect(controller.typingRun == nil)

      undoManager.undo()
      texts = try controller.segmentTexts
      #expect(
        texts.joined()
          == EditingFixture.loadedText.replacingOccurrences(of: "B5", with: "Q5"))
      #expect(undoManager.redoActionName == "Replace All")
      try controller.checkResultIsShownAsModelled()
      undoManager.undo()
      #expect(try controller.presentation.mergeResult.text == EditingFixture.loadedText)
      #expect(!undoManager.canUndo)
      undoManager.redo()
      #expect(try controller.segmentTexts[5] == "Q5\n")
      #expect(undoManager.undoActionName == "Replace All")
    }
  }

  @Test func replacingOneMatchSaysNothingOfMatchesThatAreGone() async throws {
    try await FindPasteboard.preserving {
      let (controller, driver) = try await Self.window()
      let window = try #require(controller.window)
      defer { window.close() }
      try await Self.prepare(driver, replacing: "u", matches: 5, with: "w")
      let heard = driver.announcements
      #expect(heard.last == "5 matches in 1 pane")

      driver.perform(.replace)

      #expect(try controller.presentation.mergeResult.text.filter { $0 == "u" }.count == 4)
      // The matches went with the change of the text, which is no result of a search.
      #expect(driver.announcements == heard)
    }
  }

  @Test func replaceIsAStepOfItsOwnAndTypingAfterItAnother() async throws {
    try await FindPasteboard.preserving {
      let (controller, driver) = try await Self.window()
      let window = try #require(controller.window)
      defer { window.close() }
      let undoManager = controller.sessionUndoManager
      try await Self.prepare(driver, replacing: "u8", matches: 1, with: "w8")
      driver.perform(.nextMatch)

      driver.perform(.replace)
      #expect(try controller.segmentTexts[8] == "w8\n")
      #expect(undoManager.undoActionName == "Replace")
      #expect(controller.typingRun == nil)

      // Typing right where the replacement ended is a step of its own.
      let end = try NSMaxRange(
        (controller.mergeResult.documentView.string as NSString).range(of: "w8"))
      undoManager.beginUndoGrouping()
      try controller.type("!", over: end..<end, with: .insertText)
      undoManager.endUndoGrouping()
      let typed = try controller.segmentTexts
      #expect(typed[8] == "w8!\n")
      #expect(undoManager.undoActionName == "Typing")
      undoManager.undo()
      #expect(try controller.segmentTexts[8] == "w8\n")
      #expect(undoManager.undoActionName == "Replace")
      undoManager.undo()
      #expect(try controller.presentation.mergeResult.text == EditingFixture.loadedText)
    }
  }
}
