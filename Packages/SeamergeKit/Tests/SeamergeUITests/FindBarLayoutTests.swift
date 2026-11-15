import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Checks how the panes take the find bar of the window below them: their text keeps its size
/// and scrolls to far matches, with lines that run beyond the panes and with lines that wrap,
/// and the bars of collapsed runs stay in the panes, above the find bar.
///
/// The finder keeps its search text on the find pasteboard of the system, which every app
/// shares; each test puts back what it held, whether the test passes or not.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct FindBarLayoutTests {
  /// A comparison of a thousand lines, each wider than a pane, that differ in line 500 alone.
  private static func longLines() async throws -> Session {
    let lines = (0..<1_000).map { "row\($0) " + String(repeating: "x", count: 290) }
    var changed = lines
    changed[500] += " changed"
    func text(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }
    return try await SampleDiffs.diff(old: text(lines), new: text(changed))
  }

  /// The window of the comparison with every line shown, wrapped if `wrapsLines`, and the focus
  /// in the left pane.
  private static func window(
    wrapsLines: Bool, showsAllLines: Bool = true
  ) async throws -> (SessionWindowController, PaneView) {
    let controller = try Windows.controller(for: try await longLines())
    if showsAllLines {
      controller.presentation.showAllRows()
    }
    controller.presentation.wrapsLines = wrapsLines
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let pane = try #require(controller.layout.sourcePanes.first?.pane)
    controller.window?.makeFirstResponder(pane.documentView)
    return (controller, pane)
  }

  @Test(arguments: [false, true])
  func textKeepsItsSizeWhileTheFindBarIsOpenAndAfterwards(wrapsLines: Bool) async throws {
    try await FindPasteboard.preserving {
      let (controller, pane) = try await Self.window(wrapsLines: wrapsLines)
      let window = try #require(controller.window)
      defer { window.close() }
      let driver = SearchDriver(controller)
      let textView = pane.documentView
      let size = textView.frame.size
      if wrapsLines {
        // Each line takes several screen lines.
        #expect(size.height > 2_000 * pane.theme.rowHeight)
      } else {
        #expect(size.height == 1_000 * pane.theme.rowHeight)
        #expect(size.width > textView.visibleRect.width)
      }
      let paneHeight = pane.frame.height

      #expect(try driver.send(.find))
      window.contentView?.layoutSubtreeIfNeeded()
      #expect(driver.search.findBar.barHeight > 0)
      #expect(pane.frame.height < paneHeight)
      #expect(textView.frame.size == size)

      driver.search.perform(.hideFindInterface)
      window.contentView?.layoutSubtreeIfNeeded()
      #expect(pane.frame.height == paneHeight)
      #expect(textView.frame.size == size)
    }
  }

  @Test(arguments: [false, true])
  func findNextBringsAMatchOutsideTheViewIntoViewWhileTheFindBarIsOpen(
    wrapsLines: Bool
  ) async throws {
    try await FindPasteboard.preserving {
      let (controller, pane) = try await Self.window(wrapsLines: wrapsLines)
      let window = try #require(controller.window)
      defer { window.close() }
      let driver = SearchDriver(controller)
      let textView = pane.documentView
      #expect(try driver.send(.find))
      try driver.type("row800 ")
      await driver.waitForMatches(count: 2)
      window.makeFirstResponder(textView)
      textView.setSelectedRange(NSRange(location: 0, length: 0))
      window.contentView?.layoutSubtreeIfNeeded()

      #expect(try driver.send(.findNext))

      let start = (textView.string as NSString).range(of: "row800 ")
      #expect(textView.selectedRange() == start)
      let onScreen = textView.firstRect(forCharacterRange: start, actualRange: nil)
      let place = textView.convert(window.convertFromScreen(onScreen), from: nil)
      #expect(textView.visibleRect.contains(place))
    }
  }

  @Test func barsOfCollapsedRunsStayInThePanesAboveTheFindBar() async throws {
    try await FindPasteboard.preserving {
      let (controller, pane) = try await Self.window(wrapsLines: false, showsAllLines: false)
      let window = try #require(controller.window)
      defer { window.close() }
      let driver = SearchDriver(controller)
      // The run after the change starts in view, so that its bar lies where the bar opens.
      controller.presentation.jump(to: 0)
      window.contentView?.layoutSubtreeIfNeeded()
      #expect(try driver.send(.find))
      window.contentView?.layoutSubtreeIfNeeded()
      let content = try #require(window.contentView)
      let findBar = driver.search.findBar
      let findBarFrame = content.convert(findBar.bounds, from: findBar)
      #expect(findBarFrame.height > 0)

      let bars = Windows.panes(of: controller).flatMap { CollapsedRunBars.bars(of: $0) }
      #expect(!bars.isEmpty)
      for bar in bars {
        // The content view is not flipped: the bars lie above the find bar.
        #expect(content.convert(bar.visibleRect, from: bar).minY >= findBarFrame.maxY)
      }
      // Clicks on the find bar reach it, also below the gutters.
      for y in stride(from: findBarFrame.minY + 1, to: findBarFrame.maxY, by: 4) {
        for x in [2, findBarFrame.midX] {
          let hit = content.hitTest(content.convert(CGPoint(x: x, y: y), to: content.superview))
          #expect(hit?.isDescendant(of: findBar) == true, "at \(x), \(y)")
        }
      }
      #expect(pane.documentView.enclosingScrollView?.isFindBarVisible == false)
    }
  }
}

/// The bars of collapsed runs of unchanged lines in a view, found by their role and name.
@MainActor
enum CollapsedRunBars {
  static func bars(of view: NSView) -> [NSButton] {
    var bars: [NSButton] = []
    func collect(_ view: NSView) {
      if let button = view as? NSButton, button.accessibilityRole() == .button,
        button.accessibilityLabel()?.contains("unchanged") == true
      {
        bars.append(button)
      }
      view.subviews.forEach(collect)
    }
    collect(view)
    return bars
  }
}
