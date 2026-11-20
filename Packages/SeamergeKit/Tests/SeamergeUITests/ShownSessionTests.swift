import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// A session as a window shows it: only a merge has a result, and a comparison takes no plan of
/// one.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct ShownSessionTests {
  @Test func aLoadedMergeHasItsResultAndAComparisonNone() async throws {
    let merge = try await SampleMerges.helloWorld()
    let comparison = try await SampleDiffs.greeting()

    let shownMerge = ShownSession(loading: merge, removalNotes: [:])
    let shownComparison = ShownSession(loading: comparison, removalNotes: [:])

    let result = try #require(shownMerge.result)
    #expect(result.document.segments.count == merge.blocks.count)
    #expect(shownMerge.session.blocks == merge.blocks)
    #expect(shownComparison.result == nil)
    #expect(shownComparison.session.blocks == comparison.blocks)
  }

  @Test func theSessionOfAMergeIsThatOfItsResult() async throws {
    let merge = try await SampleMerges.helloWorld()
    let result = ResultState(session: merge, removalNotes: [:])

    let shown = ShownSession.merge(result)

    #expect(shown.session.inputs.mapValues(\.label) == merge.inputs.mapValues(\.label))
    #expect(shown.session.blocks == result.document.session.blocks)
    #expect(shown.result?.text == result.text)
  }

  @Test func aComparisonCarriesOutNoPlanOfAResult() async throws {
    let merge = try await SampleMerges.helloWorld()
    let plan = ResultDocument(session: merge).planResolvingOpenConflicts(with: [.a])
    #expect(!plan.isEmpty)
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())
    defer { controller.window?.close() }
    let texts = Windows.panes(of: controller).map(\.documentView.string)

    #expect(controller.presentation.carryOut(plan) == nil)
    #expect(controller.presentation.result == nil)
    #expect(Windows.panes(of: controller).map(\.documentView.string) == texts)
  }
}
