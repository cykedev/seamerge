import AppKit
import MergeModel
import Testing

@testable import PaneKit
@testable import SeamergeUI

/// A click on the bar of toggles of a block leaves the bar where it was, to the pixel, whatever
/// the block becomes; the top of the block stays in place too.
@MainActor
@Suite struct PillStabilityTests {
  /// A step that clicks a control of the bar of block `block`, or undoes or redoes.
  enum Step: Sendable, CustomTestStringConvertible {
    case toggle(ColorRole, ofBlock: Int)
    case reset(ofBlock: Int)
    case undo
    case redo

    var testDescription: String {
      switch self {
      case .toggle(let role, let block): "toggle \(role) of block \(block)"
      case .reset(let block): "reset block \(block)"
      case .undo: "undo"
      case .redo: "redo"
      }
    }
  }

  /// The transitions, each a block and the steps that lead to it and then through it.
  nonisolated static let transitions: [(String, Int, [Step])] = [
    // The conflict takes one line, then two, then one again.
    (
      "lines more and fewer", 1,
      [.toggle(.a, ofBlock: 1), .toggle(.b, ofBlock: 1), .toggle(.a, ofBlock: 1)]
    ),
    // A removed the lines: the preview gives way to no lines, and lines come back.
    (
      "deletion and back", 3,
      [.toggle(.a, ofBlock: 3), .toggle(.b, ofBlock: 3), .toggle(.a, ofBlock: 3)]
    ),
    // The base and B share a toggle: one source becomes two and back.
    ("shared sources", 0, [.toggle(.b, ofBlock: 0), .toggle(.a, ofBlock: 0)]),
    (
      "reset, undo and redo", 3, [.toggle(.a, ofBlock: 3), .reset(ofBlock: 3), .undo, .redo, .undo]
    ),
  ]

  @Test(arguments: transitions)
  func barThatWasClickedStaysWhereItWasWhateverItsBlockBecomes(
    transition: (String, Int, [Step])
  ) async throws {
    let (_, block, steps) = transition
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    try checkSteps(steps, keep: block, in: controller)
  }

  @Test func barStaysInAScrolledResultAndTheTopOfItsBlockToo() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let result = try controller.mergeResult
    let conflicts = controller.presentation.changes.blocks.indices.filter {
      controller.presentation.changes.blocks[$0].kind == .conflict
    }
    let block = conflicts[conflicts.count / 2]
    let row = result.displayRow(ofRow: result.content.blocks[block].rows.lowerBound)
    result.scroll(to: CGPoint(x: 0, y: CGFloat(row - 4) * result.theme.rowHeight))
    try checkSteps(
      [.toggle(.a, ofBlock: block), .toggle(.b, ofBlock: block), .reset(ofBlock: block)],
      keep: block, in: controller)
  }

  @Test func lastBlockOfTheFileKeepsItsBarWhenItLosesItsLinesAndGetsThemBack() async throws {
    let session = try await SampleMerges.merge(base: "u0\nx1\n", a: "u0\n", b: "u0\ny1\n")
    let controller = try Windows.controller(for: session)
    try #require(controller.presentation.changes.blocks.count == 1)
    try checkSteps(
      [.toggle(.b, ofBlock: 0), .toggle(.a, ofBlock: 0), .toggle(.b, ofBlock: 0)], keep: 0,
      in: controller)
  }

  /// The hold ends with anything else that changes the layout, and the bar stands beside its
  /// block again: after typing above the block, after another size of the text, and when the
  /// pointer leaves the bar.
  @Test(arguments: ["typing above", "zoom", "pointer leaves"])
  func holdEndsWithAnyOtherChangeAndTheBarStandsBesideItsBlock(change: String) async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    let column = try controller.presentation.mergeDecisionColumn
    let result = try controller.mergeResult
    // A removed the lines of block 3: its bar holds the place of the line that goes.
    try click(try segment(.a, ofBlock: 3, in: column))
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    var row = try self.row(ofBlock: 3, in: column)
    var top = try #require(result.top(ofBlock: 3))
    #expect(abs(row.frame.midY - (top + result.theme.rowHeight / 2)) <= 0.5, "held")
    switch change {
    case "typing above":
      try controller.type("one\ntwo\nthree\n", over: 0..<0, with: .insertText)
    case "zoom":
      controller.perform(.zoomIn)
    default:
      let window = try #require(controller.window)
      let event = try #require(
        NSEvent.enterExitEvent(
          with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0,
          userData: nil))
      column.mouseExited(with: event)
    }
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    row = try self.row(ofBlock: 3, in: column)
    top = try #require(result.top(ofBlock: 3))
    // The block has no lines; its bar stands on the boundary where they were.
    #expect(
      abs(row.frame.midY - top) <= 0.5, "\(change): bar at \(row.frame.midY), block at \(top)")
  }

  /// Takes `steps` and checks after each that the bar of `block` and the top of the block stand
  /// where they stood before the first.
  private func checkSteps(
    _ steps: [Step], keep block: Int, in controller: SessionWindowController
  ) throws {
    let column = try controller.presentation.mergeDecisionColumn
    let result = try controller.mergeResult
    // The first click pins the bar where it stands then.
    let bar = try frameOfBar(ofBlock: block, in: column)
    let top = topOfBlock(block, in: result)
    for (index, step) in steps.enumerated() {
      switch step {
      case .toggle(let role, let block): try click(try segment(role, ofBlock: block, in: column))
      case .reset(let block): try click(try resetArrow(ofBlock: block, in: column))
      case .undo: controller.sessionUndoManager.undo()
      case .redo: controller.sessionUndoManager.redo()
      }
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      #expect(try frameOfBar(ofBlock: block, in: column) == bar, "after step \(index): \(step)")
      #expect(topOfBlock(block, in: result) == top, "after step \(index): \(step)")
    }
  }

  /// Clicks `control`, which presses it.
  private func click(_ control: DecisionControl) throws {
    control.performClick(nil)
  }

  private func row(ofBlock block: Int, in column: DecisionColumnView) throws -> DecisionRow {
    try #require(column.rows.first { $0.block == block }, "block \(block) has no row")
  }

  private func segment(
    _ role: ColorRole, ofBlock block: Int, in column: DecisionColumnView
  ) throws -> DecisionToggleButton {
    let segments = try row(ofBlock: block, in: column).controls.compactMap {
      $0 as? DecisionToggleButton
    }
    return try #require(segments.first { $0.role == role })
  }

  private func resetArrow(ofBlock block: Int, in column: DecisionColumnView) throws
    -> ResetBlockButton
  {
    try #require(
      try row(ofBlock: block, in: column).controls.compactMap { $0 as? ResetBlockButton }.first)
  }

  /// The frame of the row of `block` in the window.
  private func frameOfBar(ofBlock block: Int, in column: DecisionColumnView) throws -> CGRect {
    column.convert(try row(ofBlock: block, in: column).frame, to: nil)
  }

  /// The top of the first row of `block`, or of the boundary it lies on, in the window.
  private func topOfBlock(_ block: Int, in pane: PaneView) -> CGFloat {
    let row = pane.displayRow(ofRow: pane.content.blocks[block].rows.lowerBound)
    let text = pane.documentView
    return text.convert(CGPoint(x: 0, y: CGFloat(row) * pane.theme.rowHeight), to: nil).y
  }
}
