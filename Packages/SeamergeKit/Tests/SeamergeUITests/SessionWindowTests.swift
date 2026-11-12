import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The window around the panes: their order and sizes, and how the window ends.
@MainActor
@Suite struct SessionWindowTests {
  @Test func panesStandInTheOrderABaseB() async throws {
    let controller = makeController(try await SampleMerges.helloWorld())
    #expect(controller.layout.sourcePanes.map(\.role) == [.a, .base, .b])
  }

  @Test func mergeWithoutABaseHasNoBasePane() async throws {
    let session = try await SampleMerges.merge(
      base: nil, a: "same\nfrom a\nsame again\n", b: "same\nfrom b\nsame again\n")
    #expect(makeController(session).layout.sourcePanes.map(\.role) == [.a, .b])
  }

  @Test func closingReportsCancelledExactlyOnce() async throws {
    let controller = makeController(try await SampleMerges.helloWorld())
    var outcomes: [SessionOutcome] = []
    controller.onFinish = { outcomes.append($0) }
    let window = try #require(controller.window)
    window.close()
    window.close()
    #expect(outcomes.count == 1)
    #expect(outcomes.first.map { if case .cancelled = $0 { true } else { false } } == true)
  }

  @Test func windowUsesTheUndoManagerOfTheSessionAndHasNoTabs() async throws {
    let session = try await SampleMerges.helloWorld()
    let undoManager = UndoManager()
    let controller = SessionWindowController(session: session, undoManager: undoManager)
    let window = try #require(controller.window)
    #expect(window.undoManager === undoManager)
    #expect(window.tabbingMode == .disallowed)
  }

  @Test func newWindowGivesTheSourcesEqualWidthsAndMoreThanHalfTheHeight() async throws {
    let controller = makeController(try await SampleMerges.helloWorld())
    let widths = controller.layout.sourcePanes.map(\.pane.frame.width)
    #expect(widths.max().map { $0 - (widths.min() ?? 0) <= 1 } == true)
    let sources = try #require(controller.layout.splitViewItems.first?.viewController.view)
    let fraction = sources.frame.height / controller.layout.splitView.bounds.height
    #expect(abs(fraction - WindowMetrics.sourcesFraction) < 0.01)
  }

  @Test func smallestWindowKeepsEveryPaneAtItsLeastWidth() async throws {
    let controller = makeController(try await SampleMerges.helloWorld())
    let window = try #require(controller.window)
    window.setContentSize(window.contentMinSize)
    window.contentView?.layoutSubtreeIfNeeded()
    for (_, pane) in controller.layout.sourcePanes {
      #expect(pane.frame.width >= pane.minimumWidth)
    }
    #expect(controller.layout.view.frame.height <= window.contentMinSize.height)
  }

  @Test func changingTheDisplayOptionsRedrawsWithTheirTheme() async throws {
    let controller = makeController(try await SampleMerges.helloWorld())
    controller.displayOptions = DisplayOptions(differentiatesWithoutColor: true)
    for pane in controller.layout.sourcePanes.map(\.pane) + [controller.layout.resultPane] {
      #expect(pane.theme.differentiatesWithoutColor)
    }
  }

  private func makeController(_ session: Session) -> SessionWindowController {
    SessionWindowController(
      session: session, undoManager: UndoManager(), displayOptions: DisplayOptions())
  }
}
