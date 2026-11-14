import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Wrap Lines: for every pane of every window and across launches, with the rows of the inputs
/// level and the line at the reading line kept in place.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct LineWrappingWindowTests {
  @Test func wrapLinesWrapsEveryPaneOfEveryWindowAndStaysForTheNextOne() async throws {
    let defaults = UserDefaults.privateSuite()
    let session = try await Self.merge()
    let first = try Windows.controller(for: session, defaults: defaults)
    let second = try Windows.controller(for: session, defaults: defaults)
    let item = NSMenuItem(
      title: SessionCommand.toggleLineWrapping.title,
      action: SessionCommand.toggleLineWrapping.action, keyEquivalent: "")
    #expect(first.validateUserInterfaceItem(item) && item.state == .off)
    #expect(Windows.panes(of: first).allSatisfy { !$0.wrapsLines })

    first.toggleLineWrapping(nil)

    for controller in [first, second] {
      #expect(Windows.panes(of: controller).allSatisfy { $0.wrapsLines })
      #expect(controller.content.footer.button(of: .lineWrapping)?.state == .on)
    }
    #expect(second.validateUserInterfaceItem(item) && item.state == .on)
    #expect(LineWrapping(defaults: defaults).isOn)
    let third = try Windows.controller(for: session, defaults: defaults)
    #expect(Windows.panes(of: third).allSatisfy { $0.wrapsLines })

    second.toggleLineWrapping(nil)
    #expect(Windows.panes(of: first).allSatisfy { !$0.wrapsLines })
  }

  @Test(arguments: [CGFloat(820), 1_400])
  func rowsOfTheInputsStayLevelWhileTheirLinesWrap(width: CGFloat) async throws {
    let defaults = UserDefaults.privateSuite()
    LineWrapping(defaults: defaults).isOn = true
    let controller = try Windows.controller(for: try await Self.merge(), defaults: defaults)
    let window = try #require(controller.window)
    window.setContentSize(CGSize(width: width, height: 700))
    window.contentView?.layoutSubtreeIfNeeded()
    let panes = controller.layout.sourcePanes.map(\.pane)
    let rowCount = panes[0].content.lineNumbers.count
    let rowHeight = panes[0].theme.rowHeight
    #expect(
      (0..<rowCount).contains { row in
        let span = panes[0].verticalSpan(ofRows: row..<row + 1)
        return span.upperBound - span.lowerBound > rowHeight
      }, "some rows wrap")
    for row in 0..<rowCount {
      let spans = panes.map { $0.verticalSpan(ofRows: row..<row + 1) }
      #expect(spans.allSatisfy { $0 == spans[0] }, "row \(row)")
    }
  }

  @Test func turningWrappingOnKeepsTheLineAtTheReadingLine() async throws {
    let defaults = UserDefaults.privateSuite()
    let controller = try Windows.controller(for: try await Self.merge(), defaults: defaults)
    let pane = controller.layout.sourcePanes[0].pane
    controller.go(toLine: 40, in: pane)
    let before = pane.rowAtReadingLine.row

    controller.toggleLineWrapping(nil)

    #expect(pane.rowAtReadingLine.row == before)
  }

  /// A merge whose sides change long lines differently, the first in conflict, among enough
  /// short lines to scroll.
  static func merge() async throws -> Session {
    let long = "let message = " + Array(repeating: "\"words\"", count: 30).joined(separator: " + ")
    var base = (1...80).map { "let line\($0) = \($0)" }
    base[2] = long
    var a = base
    var b = base
    a[2] = long + " + \"from A\""
    b[2] = long + " + \"from B\""
    a[30] = "let wider = " + long
    b[50] = long + long
    func text(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }
    return try await SampleMerges.merge(base: text(base), a: text(a), b: text(b))
  }
}
