import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The commands that choose the sources of a block in the context menu of the result and in the
/// Merge menu: only those with an effect of their own, and a checkmark at the one whose outcome
/// the block holds, in each state of the block.
@MainActor
@Suite struct ResultChoiceMenuTests {
  /// A state of a block of the nine blocks of ``EditingFixture``, how to bring it about, and the
  /// decisions that the context menu offers then.
  struct Case: Sendable, CustomTestStringConvertible {
    var name: String
    var block: Int
    var commands: [SessionCommand]
    var typesInto = false
    var entries: [String]

    var testDescription: String { name }
  }

  nonisolated static let cases = [
    Case(
      name: "open conflict", block: 1, commands: [],
      entries: [
        "Use A", "Use B", "Use A Then B", "Use B Then A", "Use Base", "Use None",
        "Resolve Manually",
      ]),
    // The base and B share a toggle, so Use Base does what Use B does.
    Case(
      name: "taken automatically", block: 0, commands: [],
      entries: [
        "Use A ✓", "Use B", "Use A Then B", "Use B Then A", "Use None", "Resolve Manually",
      ]),
    Case(
      name: "one source chosen", block: 1, commands: [.useB],
      entries: [
        "Use A", "Use B ✓", "Use A Then B", "Use B Then A", "Use Base", "Use None",
        "Resolve Manually",
      ]),
    Case(
      name: "A then B", block: 1, commands: [.useAThenB],
      entries: [
        "Use A", "Use B", "Use A Then B ✓", "Use B Then A", "Use Base", "Use None",
        "Resolve Manually",
      ]),
    Case(
      name: "B then A by toggles", block: 1, commands: [.toggleSourceB, .toggleSourceA],
      entries: [
        "Use A", "Use B", "Use A Then B", "Use B Then A ✓", "Use Base", "Use None",
        "Resolve Manually",
      ]),
    Case(
      name: "base", block: 1, commands: [.useBase],
      entries: [
        "Use A", "Use B", "Use A Then B", "Use B Then A", "Use Base ✓", "Use None",
        "Resolve Manually",
      ]),
    Case(
      name: "nothing", block: 1, commands: [.useNone],
      entries: [
        "Use A", "Use B", "Use A Then B", "Use B Then A", "Use Base", "Use None ✓",
        "Resolve Manually",
      ]),
    Case(
      name: "edited by hand", block: 1, commands: [.useA], typesInto: true,
      entries: [
        "Use A", "Use B", "Use A Then B", "Use B Then A", "Use Base", "Use None",
        "Resolve Manually",
      ]),
    // A removed the lines: taking B after A takes only B, and A after B only A.
    Case(
      name: "beside a deletion", block: 3, commands: [.useB],
      entries: ["Use A", "Use B ✓", "Use Base", "Use None", "Resolve Manually"]),
  ]

  @Test(arguments: cases)
  func contextMenuOffersTheDistinctChoicesAndChecksTheOneTheBlockHolds(case: Case) async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    try bring(controller, to: `case`)
    let menu = try menu(in: controller, atBlock: `case`.block)
    let decisions = Array(entries(of: menu).prefix { $0 != "—" })
    #expect(decisions == `case`.entries)
    // The Merge menu checks the same command.
    let checked = `case`.entries.first { $0.hasSuffix(" ✓") }.map { String($0.dropLast(2)) }
    #expect(checkedChoices(in: controller) == (checked.map { [$0] } ?? []))
  }

  @Test func sidesWithTheSameTextOfferOnlyTheSimplestOfTheChoicesThatGiveIt() async throws {
    let session = try await SampleMerges.merge(
      base: "u0\nx1\nu2\n", a: "u0\ny1\nu2\n", b: "u0\ny1\nu2\n")
    let controller = try Windows.controller(for: session)
    controller.presentation.setCurrentBlock(0)
    let menu = try menu(in: controller, atBlock: 0)
    #expect(
      Array(entries(of: menu).prefix { $0 != "—" }) == [
        "Use A ✓", "Use Base", "Use None", "Resolve Manually",
      ])
    #expect(checkedChoices(in: controller) == ["Use A"])
  }

  @Test func choosingTheCheckedEntryChangesNothing() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    controller.presentation.setCurrentBlock(1)
    controller.perform(.useB)
    controller.presentation.setCurrentBlock(1)
    let texts = try controller.segmentTexts
    let menu = try menu(in: controller, atBlock: 1)
    let checked = try #require(menu.items.first { $0.state == .on })
    NSApplication.shared.sendAction(try #require(checked.action), to: checked.target, from: checked)
    #expect(try controller.segmentTexts == texts)
  }

  private func bring(_ controller: SessionWindowController, to case: Case) throws {
    controller.presentation.setCurrentBlock(`case`.block)
    for command in `case`.commands {
      controller.perform(command)
      // Deciding an open conflict goes on to the next one.
      controller.presentation.setCurrentBlock(`case`.block)
    }
    if `case`.typesInto {
      let block = controller.presentation.changes.blocks[`case`.block]
      let start = try controller.presentation.mergeResult.document.range(of: block).lowerBound
      try controller.type("typed", over: start..<start, with: .insertText)
      controller.presentation.setCurrentBlock(`case`.block)
    }
  }

  /// The commands of the Merge menu that choose sources and carry a checkmark.
  private func checkedChoices(in controller: SessionWindowController) -> [String] {
    SessionCommand.choices.compactMap { command in
      let item = NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
      _ = controller.validateUserInterfaceItem(item)
      return item.state == .on ? command.title : nil
    }
  }

  /// The context menu of the result at `block`, the current block, which may have no rows.
  private func menu(in controller: SessionWindowController, atBlock block: Int) throws -> NSMenu {
    let result = try controller.mergeResult
    let hit = PaneHit(row: result.content.blocks[block].rows.lowerBound, block: block)
    return controller.contextMenu(for: hit, in: result)
  }

  /// The titles of the items of `menu`, a dash for a separator and a checkmark for an item that
  /// is on.
  private func entries(of menu: NSMenu) -> [String] {
    menu.items.map { $0.isSeparatorItem ? "—" : $0.title + ($0.state == .on ? " ✓" : "") }
  }
}
