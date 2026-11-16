import AppKit
import MergeModel
import Testing

@testable import PaneKit
@testable import SeamergeUI

/// A merge window while the base is hidden compares A with B, as a comparison of two files does.
///
/// Both sides are tinted where their text differs, whichever side changed it, and neither where
/// both made the same change; the bands of the seam, the runs within the lines and the overview
/// bar follow, in either arrangement and however the base and the comparison mode are switched.
/// The marks in the gutters, the navigation and the result stay as with the base, and with the
/// base in view everything is as before.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct HiddenBaseTests {
  @Test(arguments: [false, true])
  func withoutTheBaseBothSidesAreTintedWhereTheirTextDiffers(alignsLines: Bool) async throws {
    let controller = try await window(alignsLines: alignsLines)
    try Self.expectTints(of: controller, comparingSides: false)

    controller.toggleBase(nil)
    try Self.expectTints(of: controller, comparingSides: true)

    controller.toggleBase(nil)
    try Self.expectTints(of: controller, comparingSides: false)

    controller.toggleBase(nil)
    await controller.switchComparison(to: ComparisonOptions(mode: .ignoreAllWhitespace))
    try Self.expectTints(of: controller, comparingSides: true)

    if alignsLines {
      controller.showConnectedSides(nil)
    } else {
      controller.showAlignedLines(nil)
    }
    try Self.expectTints(of: controller, comparingSides: true)
  }

  @Test func withoutTheBaseABandConnectsTheTintedLinesOfAAndBWhereverTheyDiffer() async throws {
    let controller = try await window(alignsLines: false)
    controller.toggleBase(nil)
    let changes = controller.presentation.changes
    let seam = try #require(controller.layout.seams.first)
    let hairline = 1 / (controller.window?.backingScaleFactor ?? 2)
    for (index, block) in changes.blocks.enumerated() {
      controller.presentation.jump(to: index)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      let band = seam.bands.first { $0.block == index }
      guard block.kind != .changedInBoth else {
        #expect(band == nil, "block \(index): A and B have the same text")
        continue
      }
      let found = try #require(band, "block \(index) of kind \(block.kind) has no band")
      #expect(found.leftStyle == .tinted(.a) && found.rightStyle == .tinted(.b), "block \(index)")
      // An end spans the lines of its side, also the lines a side kept where only the other side
      // changed the block, and is a point only where the side has no lines.
      for (end, role) in [(found.left, Role.a), (found.right, .b)] {
        let lines = block.lines(in: role).count
        if lines == 0 {
          #expect(end.lowerBound == end.upperBound, "block \(index) on \(role)")
        } else {
          let height = end.upperBound - end.lowerBound + hairline
          #expect(height >= CGFloat(lines) * Theme().rowHeight - 0.5, "block \(index) on \(role)")
        }
      }
    }
  }

  @Test func withoutTheBaseTheRunsWithinTheLinesCompareAWithB() async throws {
    let controller = try await window(alignsLines: true)
    let changes = controller.presentation.changes
    let (a, b) = try panes(of: controller)
    func expectRuns(comparingSides: Bool) throws {
      for (index, block) in changes.blocks.enumerated() {
        let expected = try changes.session.inlineHighlights(
          for: block, comparingSides: comparingSides)
        for (role, pane) in [(Role.a, a), (.b, b)] {
          let runs = try #require(pane.highlightProvider).highlights(forBlock: index)
          #expect(runs == expected.ranges(in: role), "block \(index) on \(role)")
        }
      }
    }
    try expectRuns(comparingSides: false)
    // A side that did not change a block has runs only while it is compared with the other.
    let differingRuns = try changes.blocks.map {
      try changes.session.inlineHighlights(for: $0, comparingSides: true).ranges(in: .b)
    }
    let onlyA = try #require(
      changes.blocks.indices.first {
        changes.blocks[$0].kind == .changedInA && !differingRuns[$0].isEmpty
      })
    #expect(try #require(b.highlightProvider).highlights(forBlock: onlyA).isEmpty)

    controller.toggleBase(nil)

    try expectRuns(comparingSides: true)
    #expect(try !(#require(b.highlightProvider).highlights(forBlock: onlyA).isEmpty))
  }

  @Test func withoutTheBaseTheOverviewBarMarksBothSidesWhereTheyDiffer() async throws {
    let controller = try await window(alignsLines: false)
    let changes = controller.presentation.changes
    let bar = controller.presentation.sourcesOverviewBar
    func placements(of index: Int) -> Set<OverviewMark.Placement> {
      Set(bar.marks.filter { $0.block == index }.map(\.placement))
    }
    for (index, block) in changes.blocks.enumerated() where block.kind != .conflict {
      let changers = SessionChanges.changers(of: block)
      let expected = Set(
        [(Role.a, OverviewMark.Placement.leading), (.b, .trailing)].filter {
          changers.contains($0.0)
        }.map(\.1))
      #expect(placements(of: index) == expected, "block \(index)")
    }

    controller.toggleBase(nil)

    for (index, block) in changes.blocks.enumerated() where block.kind != .conflict {
      let expected: Set<OverviewMark.Placement> =
        block.kind == .changedInBoth ? [] : [.leading, .trailing]
      #expect(placements(of: index) == expected, "block \(index)")
    }
    // A mark of the side that kept the lines names the side that changed them.
    let onlyA = try #require(changes.blocks.firstIndex { $0.kind == .changedInA })
    let labels = Set(bar.marks.filter { $0.block == onlyA }.map(\.accessibilityLabel))
    #expect(labels.count == 1 && labels.first?.hasPrefix("Change in A") == true, "\(labels)")
  }

  @Test func withoutTheBaseNextChangeStillStopsAtAChangeBothMadeAndShowsItAsCurrent() async throws {
    let controller = try await window(alignsLines: false)
    controller.toggleBase(nil)
    let changes = controller.presentation.changes
    let same = try #require(
      changes.blocks.indices.first { $0 > 0 && changes.blocks[$0].kind == .changedInBoth })
    controller.presentation.jump(to: same - 1)

    controller.perform(.nextChange)

    #expect(controller.presentation.currentBlock == same)
    let (a, b) = try panes(of: controller)
    for pane in [a, b] {
      #expect(pane.currentBlock == same)
      #expect(pane.content.blocks[same].style == .unchanged)
      // The rows of the current block have a tint of their own on a pane that leaves them
      // untinted.
      #expect(pane.theme.rowFill(for: .unchanged, isFiller: false, isCurrent: true) != nil)
    }
  }

  @Test func hidingTheBaseLeavesTheResultAndItsDecisionsAsTheyAre() async throws {
    let controller = try await window(alignsLines: false)
    let result = try controller.mergeResult
    let text = result.content.text
    let blocks = result.content.blocks

    controller.toggleBase(nil)

    #expect(result.content.text == text)
    #expect(result.content.blocks == blocks)
  }

  /// Expects the tint of every block on the panes of A and B: as each side changed it against the
  /// base, or where A and B differ if `comparingSides`.
  private static func expectTints(
    of controller: SessionWindowController, comparingSides: Bool
  ) throws {
    let changes = controller.presentation.changes
    let a = try #require(controller.layout.sourcePane(.a))
    let b = try #require(controller.layout.sourcePane(.b))
    for (index, block) in changes.blocks.enumerated() {
      let changers = SessionChanges.changers(of: block)
      let differ = block.kind != .changedInBoth
      for (role, pane) in [(Role.a, a), (.b, b)] {
        let isTinted = comparingSides ? differ : changers.contains(role)
        let expected: BlockStyle = isTinted ? .tinted(role.colorRole) : .unchanged
        #expect(pane.content.blocks[index].style == expected, "block \(index) on \(role)")
      }
    }
  }

  /// A window of the example merge, which has changes of A, of B, of both alike and conflicts,
  /// lining up its lines or connecting its changes.
  private func window(alignsLines: Bool) async throws -> SessionWindowController {
    let settings = UserSettings.private()
    settings.alignsLines = alignsLines
    let controller = try Windows.controller(
      for: try await SampleMerges.example(), settings: settings)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let kinds = Set(controller.presentation.changes.blocks.map(\.kind))
    try #require(kinds.isSuperset(of: [.changedInA, .changedInB, .changedInBoth, .conflict]))
    return controller
  }

  private func panes(of controller: SessionWindowController) throws -> (PaneView, PaneView) {
    (
      try #require(controller.layout.sourcePane(.a)),
      try #require(controller.layout.sourcePane(.b))
    )
  }
}
