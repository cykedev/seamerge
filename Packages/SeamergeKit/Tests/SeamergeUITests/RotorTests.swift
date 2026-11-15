import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Checks the rotors of VoiceOver: through the conflicts of a merge and through every change,
/// block by block, in the text of the pane that has the focus.
@MainActor
@Suite struct RotorTests {
  @Test func mergeOffersConflictsAndChangesInEveryPane() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks(lineCount: 20))
    defer { controller.window?.close() }
    for pane in controller.presentation.allPanes {
      let labels = pane.documentView.accessibilityCustomRotors().map(\.label)
      #expect(labels == ["Conflicts", "Changes"])
    }
  }

  @Test func comparisonOffersOnlyChanges() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())
    defer { controller.window?.close() }
    let pane = try #require(controller.presentation.allPanes.last)
    #expect(pane.documentView.accessibilityCustomRotors().map(\.label) == ["Changes"])
  }

  @Test func conflictsRotorGoesThroughTheConflictsOfTheResultAndSaysWhetherTheyAreOpen()
    async throws
  {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks(lineCount: 20))
    defer { controller.window?.close() }
    let result = try #require(controller.presentation.layout.resultPane)
    try #require(controller.window).makeFirstResponder(result.documentView)
    let rotor = try Self.rotor("Conflicts", of: result)
    let blocks = controller.presentation.changes.blocks
    let conflicts = blocks.indices.filter { blocks[$0].kind == .conflict }
    #expect(conflicts.count == 2)

    let first = try #require(Self.search(rotor, after: nil))
    #expect(first.customLabel == "Conflict 1 of 2, open")
    #expect(first.targetElement === result.documentView)
    #expect(first.targetRange == Self.range(of: conflicts[0], in: result))
    let second = try #require(Self.search(rotor, after: first))
    #expect(second.customLabel == "Conflict 2 of 2, open")
    #expect(second.targetRange == Self.range(of: conflicts[1], in: result))
    #expect(Self.search(rotor, after: second) == nil)
    #expect(
      Self.search(rotor, after: second, direction: .previous)?.customLabel == first.customLabel)
    #expect(Self.search(rotor, after: nil, direction: .previous)?.customLabel == second.customLabel)

    // The item, not its range, tells where VoiceOver is: blocks without rows share ranges.
    second.targetRange = first.targetRange
    #expect(Self.search(rotor, after: second) == nil)
    #expect(
      Self.search(rotor, after: second, direction: .previous)?.customLabel == first.customLabel)

    // An item that the rotor did not give out is found by its range.
    let copy = NSAccessibilityCustomRotor.ItemResult(targetElement: result.documentView)
    copy.targetRange = first.targetRange
    #expect(Self.search(rotor, after: copy)?.customLabel == second.customLabel)
    #expect(Self.search(rotor, after: copy, direction: .previous) == nil)

    controller.resolveOpenConflicts(with: [.a])
    #expect(Self.search(rotor, after: nil)?.customLabel == "Conflict 1 of 2, resolved")
  }

  @Test func changesRotorFollowsTheFocusAndFiltersBySpokenName() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks(lineCount: 20))
    defer { controller.window?.close() }
    let window = try #require(controller.window)
    let pane = try #require(controller.presentation.layout.sourcePanes.first?.pane)
    window.makeFirstResponder(pane.documentView)
    let rotor = try Self.rotor("Changes", of: pane)
    let count = controller.presentation.changes.blocks.count

    let first = try #require(Self.search(rotor, after: nil))
    #expect(first.targetElement === pane.documentView)
    #expect(first.customLabel == "Change 1 of \(count)")
    #expect(first.targetRange == Self.range(of: 0, in: pane))
    let filtered = try #require(Self.search(rotor, after: nil, filter: "\(count) of"))
    #expect(filtered.customLabel == "Change \(count) of \(count)")
  }

  private static func rotor(_ label: String, of pane: PaneView) throws
    -> NSAccessibilityCustomRotor
  {
    try #require(pane.documentView.accessibilityCustomRotors().first { $0.label == label })
  }

  private static func search(
    _ rotor: NSAccessibilityCustomRotor, after item: NSAccessibilityCustomRotor.ItemResult?,
    direction: NSAccessibilityCustomRotor.SearchDirection = .next, filter: String = ""
  ) -> NSAccessibilityCustomRotor.ItemResult? {
    let parameters = NSAccessibilityCustomRotor.SearchParameters()
    parameters.currentItem = item
    parameters.searchDirection = direction
    parameters.filterString = filter
    return rotor.itemSearchDelegate?.rotor(rotor, resultFor: parameters)
  }

  private static func range(of block: Int, in pane: PaneView) -> NSRange {
    pane.textRange(ofRows: pane.content.blocks[block].rows)
  }
}
