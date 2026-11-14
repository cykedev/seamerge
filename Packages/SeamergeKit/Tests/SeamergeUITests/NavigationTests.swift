import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Jumps from conflict to conflict and from change to change: which blocks they reach, that they
/// stop at the end, where the block comes to rest, and when the commands are valid.
@MainActor
@Suite struct NavigationTests {
  @Test func conflictJumpsVisitTheOpenConflictsInOrderAndStopAtTheEnd() {
    let open = [false, true, false, false, true, true, false]
    var navigation = BlockNavigation(isOpenConflict: open, current: nil)
    var visited: [Int] = []
    while let next = navigation.nextOpenConflict {
      visited.append(next)
      navigation = BlockNavigation(isOpenConflict: open, current: next)
    }
    #expect(visited == [1, 4, 5])
    var back: [Int] = []
    while let previous = navigation.previousOpenConflict {
      back.append(previous)
      navigation = BlockNavigation(isOpenConflict: open, current: previous)
    }
    #expect(back == [4, 1])
    #expect(BlockNavigation(isOpenConflict: open, current: nil).previousOpenConflict == nil)
    #expect(BlockNavigation(isOpenConflict: open, current: 3).openConflictCount == 3)
  }

  @Test func changeJumpsVisitEveryChangedBlockAndStopAtTheEnd() {
    let open = [false, true, false]
    #expect(BlockNavigation(isOpenConflict: open, current: nil).nextChange == 0)
    #expect(BlockNavigation(isOpenConflict: open, current: 1).nextChange == 2)
    #expect(BlockNavigation(isOpenConflict: open, current: 2).nextChange == nil)
    #expect(BlockNavigation(isOpenConflict: open, current: 0).previousChange == nil)
    #expect(BlockNavigation(isOpenConflict: open, current: 1).firstChange == 0)
    #expect(BlockNavigation(isOpenConflict: open, current: 0).firstChange == nil)
    #expect(BlockNavigation(isOpenConflict: open, current: 1).lastChange == 2)
    #expect(BlockNavigation(isOpenConflict: open, current: 2).lastChange == nil)
    #expect(BlockNavigation(isOpenConflict: [], current: nil).nextChange == nil)
  }

  @Test func conflictCommandsOfTheWindowVisitItsOpenConflictsAndThenAreInvalid() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let window = try #require(controller.window)
    let presentation = controller.presentation
    let document = try presentation.mergeResult.document
    let open = presentation.changes.blocks.indices.filter {
      document.segment(for: presentation.changes.blocks[$0]).state == .open
    }
    #expect(open.count > 10)
    var visited = [try #require(presentation.currentBlock)]
    while controller.canPerform(.nextConflict) {
      #expect(window.tryToPerform(SessionCommand.nextConflict.action, with: nil))
      visited.append(try #require(presentation.currentBlock))
    }
    #expect(visited == open)
    let item = NSMenuItem(title: "", action: SessionCommand.nextConflict.action, keyEquivalent: "")
    #expect(!controller.validateUserInterfaceItem(item))
    item.action = SessionCommand.previousConflict.action
    #expect(controller.validateUserInterfaceItem(item))
  }

  @Test func changeCommandsOfTheWindowVisitEveryChangedBlock() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let presentation = controller.presentation
    controller.selectLastChange(nil)
    #expect(presentation.currentBlock == presentation.changes.blocks.count - 1)
    #expect(!controller.canPerform(.nextChange))
    #expect(!controller.canPerform(.lastChange))
    var visited: [Int] = []
    while controller.canPerform(.previousChange) {
      controller.selectPreviousChange(nil)
      visited.append(try #require(presentation.currentBlock))
    }
    #expect(visited == Array((0..<presentation.changes.blocks.count - 1).reversed()))
    #expect(!controller.canPerform(.firstChange))
  }

  @Test func jumpPutsTheBlockAtTheReadingLineOfEveryPane() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let presentation = controller.presentation
    for block in [20, 7, 31] {
      presentation.jump(to: block)
      for pane in Windows.panes(of: controller) {
        let readingLine = (pane.documentView.visibleRect.height * Theme.readingLine).rounded()
        let row = pane.content.blocks[block].rows.lowerBound
        let top =
          pane.verticalSpan(ofRows: row..<row + 1).lowerBound - Windows.scrollOffset(of: pane)
        #expect(abs(top - readingLine) <= pane.theme.rowHeight, "block \(block)")
        #expect(pane.currentBlock == block)
      }
    }
  }

  @Test func menusHoldEveryCommandOnce() {
    let inMenus = SessionCommand.Menu.allCases.flatMap { SessionCommand.groups(in: $0) }.joined()
    #expect(inMenus.count == SessionCommand.allCases.count)
    #expect(Set(inMenus.map(\.action)) == Set(SessionCommand.allCases.map(\.action)))
    #expect(SessionCommand.allCases.allSatisfy { SessionCommand(action: $0.action) == $0 })
  }

  @Test func jumpsFollowTheKeysOfTheConcept() {
    let option: NSEvent.ModifierFlags = [.option, .command]
    let shift: NSEvent.ModifierFlags = [.shift, .option, .command]
    let down = SessionCommand.downArrow
    let up = SessionCommand.upArrow
    #expect(Keys.of(.nextConflict, in: .merge) == Keys(down, option))
    #expect(Keys.of(.previousConflict, in: .merge) == Keys(up, option))
    #expect(Keys.of(.nextChange, in: .merge) == Keys(down, shift))
    #expect(Keys.of(.previousChange, in: .merge) == Keys(up, shift))
    // A comparison of two files counts changes in the toolbar, so the plain jumps take them.
    #expect(Keys.of(.nextChange, in: .diff) == Keys(down, option))
    #expect(Keys.of(.previousChange, in: .diff) == Keys(up, option))
    #expect(Keys.of(.nextConflict, in: .diff) == nil)
    #expect(Keys.of(.firstChange, in: .merge) == nil)
  }
}
