import AppKit
import MergeModel
import Testing

@testable import PaneKit
@testable import SeamergeUI

/// Wrap Lines turned on, off and on again far down a text whose rows wrap in one pane and stand
/// short beside them in another, and runs collapsed and expanded there while lines wrap: every
/// pane still lays out and shows the rows in view, in a merge, a comparison and a comparison of
/// connected sides.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct WrapAndDrawTests {
  @Test func everyPaneOfAMergeShowsItsRowsAfterWrappingIsSwitchedFarDown() async throws {
    let controller = try Windows.controller(for: try await Self.example())
    let pane = try #require(controller.layout.sourcePane(.base))
    controller.go(toLine: 151, in: pane)
    for step in 0..<3 {
      controller.toggleLineWrapping(nil)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      try expectEveryPaneShowsItsRows(in: controller, "step \(step)")
    }
  }

  @Test func everyPaneOfAMergeShowsItsRowsWhileRunsCollapseAndExpandFarDown() async throws {
    let settings = UserSettings.private()
    settings.wrapsLines = true
    let controller = try Windows.controller(for: try await Self.example(), settings: settings)
    let pane = try #require(controller.layout.sourcePane(.base))
    controller.go(toLine: 300, in: pane)
    for step in 0..<4 {
      if step % 2 == 0 {
        controller.showAllLines(nil)
      } else {
        controller.collapseUnchangedLines(nil)
      }
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      try expectEveryPaneShowsItsRows(in: controller, "step \(step)")
    }
  }

  @Test(arguments: [true, false])
  func everyPaneOfAComparisonShowsItsRowsAfterWrappingIsSwitchedFarDown(
    alignsLines: Bool
  ) async throws {
    let (base, a, _) = Self.texts()
    let session = try await SampleDiffs.diff(old: base, new: a, label: "Sources/Long.swift")
    let settings = UserSettings.private()
    settings.alignsLines = alignsLines
    let controller = try Windows.controller(for: session, settings: settings)
    let pane = try #require(controller.layout.sourcePane(.a))
    controller.go(toLine: 170, in: pane)
    for step in 0..<3 {
      controller.toggleLineWrapping(nil)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      try expectEveryPaneShowsItsRows(in: controller, "step \(step)")
    }
  }

  /// Expects TextKit to lay out the row at the top of every pane side by side in view, and to
  /// find that row at the top of the pane.
  private func expectEveryPaneShowsItsRows(
    in controller: SessionWindowController, _ context: String
  ) throws {
    for source in controller.layout.sourcePanes.map(\.pane) where source.isShown {
      let text = source.textView
      let visible = text.visibleRect
      let topRow = source.displayRows.row(
        atDisplayRow: source.displayRows.displayRow(atLine: Int(visible.minY / source.rowHeight)))
      let manager = try #require(text.textLayoutManager)
      let viewport = try #require(manager.textViewportLayoutController.viewportRange)
      let start = manager.offset(from: manager.documentRange.location, to: viewport.location)
      let end = manager.offset(from: manager.documentRange.location, to: viewport.endLocation)
      let rows = text.grid.row(containingOffset: start)...text.grid.row(containingOffset: end)
      #expect(rows.contains(topRow), "\(context): rows \(rows) laid out, \(topRow) at the top")
      var first: CGRect?
      manager.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
        first = fragment.layoutFragmentFrame
        return false
      }
      let frame = try #require(first)
      #expect(frame.minY <= visible.minY && frame.maxY > visible.minY, "\(context): \(frame)")
      // TextKit finds the fragment at a place by the frames it laid the fragments out at.
      let found = try #require(
        manager.textLayoutFragment(for: CGPoint(x: 0, y: visible.minY)) as? RowLayoutFragment)
      #expect(found.rows.contains(topRow), "\(context): \(found.rows) found for \(topRow)")
    }
  }

  /// The merge of the example in the repository, `OrderService.java`, whose base stands short
  /// and with filler rows beside long lines of A and B around its line 151.
  static func example() async throws -> Session {
    let examples = URL(filePath: #filePath).deletingLastPathComponent()
      .appending(path: "../../../../Examples").standardized
    func text(_ role: String) throws -> String {
      try String(
        contentsOf: examples.appending(path: "\(role)/OrderService.java"), encoding: .utf8)
    }
    return try await SampleMerges.merge(base: try text("Base"), a: try text("A"), b: try text("B"))
  }

  /// A base of 400 short lines; A inserts five lines after every twentieth of the first 150, each
  /// long enough to wrap onto a second line in a pane of the standard window, and B changes every
  /// tenth line after them; the filler rows of the base and B then stand beside the wrapped rows
  /// of A, and the text goes on far below.
  static func texts() -> (base: String, a: String, b: String) {
    let base = (0..<400).map { index in
      "let value\(index) = \(index)"
        + (index % 7 == 3 ? String(repeating: " + a term every row shares", count: 3) : "")
    }
    var a: [String] = []
    for (index, line) in base.enumerated() {
      a.append(line)
      if index < 150 && index % 20 == 0 {
        a += (0..<5).map {
          "let inserted\(index)_\($0) = \($0)"
            + String(repeating: " + another term of the sum", count: 2)
        }
      }
    }
    var b = base
    for index in stride(from: 155, to: 400, by: 10) {
      b[index] += " * 2"
    }
    func text(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }
    return (text(base), text(a), text(b))
  }
}
