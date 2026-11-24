import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Draws the pictures of the footer, the overview bars and the headers for the visual review:
/// the sample merge of P4Merge and a comparison in every look, at the least size, without
/// transparency, the number of collapsed lines with the changes of a diff in its subtitle, and
/// the overview bars scrolled to the top, the middle and the end.
@MainActor
@Suite(.serialized) struct FooterPicturesTests {
  @Test(arguments: Look.all)
  func mergeIsPicturedWithItsFooterInEveryLook(look: Look) async throws {
    try Windows.picture(
      try await SampleMerges.helloWorld(), context: SampleMerges.helloWorldContext, look: look,
      options: DisplayOptions(increasesContrast: look.increasesContrast), actsAsKey: true,
      named: "footer-merge-\(look.name)")
  }

  @Test(arguments: Look.all)
  func comparisonIsPicturedWithItsFooterInEveryLook(look: Look) async throws {
    try Windows.picture(
      try await SampleDiffs.greeting(), context: SessionContext(), look: look,
      options: DisplayOptions(increasesContrast: look.increasesContrast), actsAsKey: true,
      named: "footer-diff-\(look.name)")
  }

  @Test(arguments: Look.all)
  func hiddenLinesAndTheChangesOfADiffArePicturedInEveryLook(look: Look) async throws {
    let options = DisplayOptions(increasesContrast: look.increasesContrast)
    try Windows.picture(
      try await SampleDiffs.manyChanges(), context: SampleDiffs.gitContext, look: look,
      options: options, actsAsKey: true, named: "hidden-lines-diff-\(look.name)")
    try Windows.picture(
      try await SampleMerges.manyBlocks(lineCount: 600, spacing: 30), context: SessionContext(),
      look: look, options: options, actsAsKey: true, named: "hidden-lines-merge-\(look.name)")
  }

  @Test func hiddenLinesArePicturedWithoutColorWithoutTransparencyAndAtTheLeastSize()
    async throws
  {
    let session = try await SampleDiffs.manyChanges()
    try Windows.picture(
      session, context: SampleDiffs.gitContext, look: .light,
      options: DisplayOptions(differentiatesWithoutColor: true),
      named: "hidden-lines-diff-without-color-light")
    try Windows.picture(
      session, context: SampleDiffs.gitContext, look: .light,
      options: DisplayOptions(reducesTransparency: true),
      named: "hidden-lines-diff-reduced-transparency-light")
    try Windows.picture(
      session, context: SampleDiffs.gitContext, look: .light, size: nil,
      named: "hidden-lines-diff-smallest-light")
    try Windows.picture(
      try await SampleMerges.manyBlocks(lineCount: 600, spacing: 30), context: SessionContext(),
      look: .light, size: nil, named: "hidden-lines-merge-smallest-light")
  }

  @Test func smallestWindowsArePictured() async throws {
    try Windows.picture(
      try await SampleMerges.helloWorld(), context: SampleMerges.helloWorldContext, look: .light,
      size: nil, named: "footer-merge-smallest-light")
    try Windows.picture(
      try await SampleDiffs.greeting(), context: SessionContext(), look: .light,
      size: nil, named: "footer-diff-smallest-light")
  }

  @Test(arguments: [Look.light, .dark])
  func windowWithoutTransparencyIsPictured(look: Look) async throws {
    try Windows.picture(
      try await SampleMerges.helloWorld(), context: SampleMerges.helloWorldContext, look: look,
      options: DisplayOptions(reducesTransparency: true), actsAsKey: true,
      named: "footer-merge-reduced-transparency-\(look.name)")
  }

  @Test func windowWithTheFooterHiddenIsPictured() async throws {
    let settings = UserSettings.private()
    settings.showsFooter = false
    try Windows.picture(
      try await SampleMerges.helloWorld(), context: SampleMerges.helloWorldContext, look: .light,
      settings: settings, named: "footer-hidden-light")
  }

  @Test func togglesArePicturedInEveryState() async throws {
    let session = try await SampleMerges.manyBlocks(lineCount: 600, spacing: 30)
    try Windows.picture(
      session, context: SessionContext(), look: .light, actsAsKey: true,
      named: "footer-collapse-mixed-invisibles-on-light"
    ) { controller in
      let pane = controller.layout.sourcePanes[0].pane
      controller.presentation.pane(pane, didAskToExpand: pane.collapsedRuns[0])
      controller.toggleInvisibles(nil)
      controller.toggleScrollSynchronization(nil)
    }
  }

  @Test(arguments: Look.all, OverviewPlace.allCases)
  func overviewBarsArePicturedAtTheTopTheMiddleAndTheEnd(
    look: Look, place: OverviewPlace
  ) async throws {
    let session = try await SampleMerges.manyBlocks(lineCount: 600, spacing: 30)
    try Windows.picture(
      session, context: SessionContext(), look: look,
      options: DisplayOptions(increasesContrast: look.increasesContrast, reducesMotion: true),
      named: "overview-\(place.rawValue)-\(look.name)"
    ) { controller in
      controller.showAllLines(nil)
      for pane in Windows.panes(of: controller) {
        let text = pane.documentView
        let room = max(text.frame.height - text.visibleRect.height, 0)
        text.scroll(CGPoint(x: 0, y: room * place.fraction))
      }
    }
  }

  /// Where the overview bars are pictured.
  enum OverviewPlace: String, CaseIterable, Sendable {
    case top, middle, end

    var fraction: CGFloat {
      switch self {
      case .top: 0
      case .middle: 0.5
      case .end: 1
      }
    }
  }
}
