import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Block mode and text mode, which follow the focus: single keys as commands in a pane above the
/// result, Return into the result and Escape back, and keys without a meaning that do nothing.
@MainActor
@Suite struct BlockModeTests {
  @Test func windowOpensInBlockModeWithTheFocusInA() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let window = try #require(controller.window)
    #expect(window.firstResponder === controller.layout.sourcePane(.a)?.documentView)
    #expect(controller.isInBlockMode)
    #expect(!controller.isInTextMode)
  }

  @Test func singleKeysJumpBetweenConflictsAndChanges() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let presentation = controller.presentation
    let first = try #require(presentation.currentBlock)
    let next = try #require(presentation.navigation.nextOpenConflict)
    try press("n", in: controller)
    #expect(presentation.currentBlock == next)
    try press("N", modifiers: .shift, in: controller)
    #expect(presentation.currentBlock == first)
    try press(SessionCommand.downArrow, modifiers: [.function, .numericPad], in: controller)
    #expect(presentation.currentBlock == first + 1)
    try press(SessionCommand.upArrow, modifiers: [.function, .numericPad], in: controller)
    #expect(presentation.currentBlock == first)
    try press("\u{F72B}", modifiers: .function, in: controller)
    #expect(presentation.currentBlock == presentation.changes.blocks.count - 1)
    try press("\u{F729}", modifiers: .function, in: controller)
    #expect(presentation.currentBlock == 0)
  }

  @Test func tabMovesTheFocusThroughThePanesAndIntoTheResult() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let window = try #require(controller.window)
    let panes = Windows.panes(of: controller)
    for pane in panes.dropFirst() {
      try press("\t", in: controller)
      #expect(window.firstResponder === pane.documentView)
    }
    // In the result, Tab is a character again; Escape leaves it for the pane it came from.
    #expect(controller.isInTextMode)
    try press("\u{1B}", in: controller)
    #expect(window.firstResponder === panes[2].documentView)
    try press("\u{19}", modifiers: .shift, in: controller)
    #expect(window.firstResponder === panes[1].documentView)
    controller.selectPreviousPane(nil)
    controller.selectPreviousPane(nil)
    #expect(try window.firstResponder === controller.mergeResult.documentView)
  }

  @Test func movingTheFocusIntoTheResultKeepsItsInsertionPoint() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let window = try #require(controller.window)
    let result = try controller.mergeResult.documentView
    controller.enterTextMode()
    let caret = NSRange(location: 500, length: 0)
    result.setSelectedRange(caret)
    controller.selectNextPane(nil)
    #expect(controller.isInBlockMode)
    for _ in 0..<3 {
      controller.selectNextPane(nil)
    }
    #expect(window.firstResponder === result)
    #expect(result.selectedRange() == caret)
  }

  @Test func singleKeysOfBlockModeComeFromTheCommands() {
    #expect(SessionCommand(blockModeKey: Keystroke("n")) == .nextConflict)
    #expect(SessionCommand(blockModeKey: Keystroke("N", .shift)) == .previousConflict)
    #expect(SessionCommand(blockModeKey: Keystroke("\u{19}", .shift)) == .previousPane)
    #expect(SessionCommand(blockModeKey: Keystroke("j")) == nil)
    #expect(SessionCommand(blockModeKey: Keystroke("1")) == .useA)
    #expect(SessionCommand(blockModeKey: Keystroke("1", .option)) == .toggleSourceA)
    #expect(SessionCommand(blockModeKey: Keystroke("7")) == nil)
    let keys = SessionCommand.allCases.flatMap(\.blockModeKeys)
    for (index, key) in keys.enumerated() {
      #expect(!keys[(index + 1)...].contains(key), "\(key.key) belongs to one command")
    }
  }

  @Test func returnEntersTheResultAtTheCurrentBlockAndEscapeGoesBack() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let window = try #require(controller.window)
    let b = try #require(controller.layout.sourcePane(.b))
    window.makeFirstResponder(b.documentView)
    controller.presentation.jump(to: 8)
    try press("\r", in: controller)
    let result = try controller.mergeResult
    #expect(controller.isInTextMode)
    let caret = result.documentView.selectedRange()
    #expect(caret.length == 0)
    #expect(
      caret.location == result.content.offset(ofRow: result.content.blocks[8].rows.lowerBound))
    #expect(result.showsWhole(rows: result.content.blocks[8].rows))
    try press("\u{1B}", in: controller)
    #expect(window.firstResponder === b.documentView)
    #expect(controller.isInBlockMode)
  }

  @Test func keysWithoutAMeaningInBlockModeDoNothing() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let window = try #require(controller.window)
    let a = try #require(controller.layout.sourcePane(.a))
    a.documentView.setSelectedRange(NSRange(location: 2, length: 3))
    let current = controller.presentation.currentBlock
    let text = a.documentView.string
    for key in ["\u{7F}", "\u{F728}", "j", "k", "J", "x", " ", "7", "\u{1B}"] {
      #expect(controller.handleKeyDown(try event(key, in: window)), "key \(key)")
      #expect(controller.presentation.currentBlock == current)
      #expect(window.firstResponder === a.documentView)
      #expect(a.documentView.string == text)
      #expect(a.documentView.selectedRange() == NSRange(location: 2, length: 3))
    }
    #expect(controller.handleKeyDown(try event("1", modifiers: .option, in: window)))
  }

  @Test func commandKeysPageKeysAndTypingInTheResultPassThrough() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let window = try #require(controller.window)
    #expect(!controller.handleKeyDown(try event("c", modifiers: .command, in: window)))
    #expect(!controller.handleKeyDown(try event("\t", modifiers: .control, in: window)))
    #expect(!controller.handleKeyDown(try event("\u{F72D}", modifiers: .function, in: window)))
    controller.enterTextMode()
    #expect(!controller.handleKeyDown(try event("n", in: window)))
    #expect(!controller.handleKeyDown(try event("\r", in: window)))
  }

  /// The finder writes to the find pasteboard of the system as the find bar opens; the test puts
  /// back what it held.
  @Test func typingInTheFindBarOfTheResultTypesAndCarriesOutNoCommand() async throws {
    try await FindPasteboard.preserving {
      let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
      let window = try #require(controller.window)
      defer { window.close() }
      let result = try controller.mergeResult
      let current = controller.presentation.currentBlock
      let text = result.documentView.string
      window.makeFirstResponder(result.documentView)
      let item = NSMenuItem(
        title: "", action: #selector(NSTextView.performTextFinderAction(_:)), keyEquivalent: "")
      item.tag = NSTextFinder.Action.showFindInterface.rawValue
      result.documentView.performTextFinderAction(item)
      let field = try #require(window.firstResponder as? NSText)
      #expect(field.isDescendant(of: result))
      #expect(!controller.isInBlockMode)
      #expect(!controller.isInTextMode)
      // In block mode, "n" and "2" jump to the next conflict and take B; the others do nothing.
      for key in ["n", "2", " ", "x"] {
        try press(key, in: controller)
      }
      #expect(field.string == "n2 x")
      #expect(controller.presentation.currentBlock == current)
      #expect(result.documentView.string == text)
    }
  }
}
