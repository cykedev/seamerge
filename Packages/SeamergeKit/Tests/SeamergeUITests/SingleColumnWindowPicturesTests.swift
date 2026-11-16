import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// Draws the pictures of a comparison in a single column: an insertion, a change and a removal
/// in every look, without color, with reduced transparency, in the smallest window, with
/// wrapped lines and with collapsed runs; and the choice of the arrangement in the toolbars of
/// a comparison and a merge in every look.
@MainActor
@Suite(.serialized) struct SingleColumnWindowPicturesTests {
  @Test(arguments: Look.all)
  func singleColumnIsPicturedInEveryLook(look: Look) async throws {
    try Windows.picture(
      try await SampleDiffs.greeting(), context: SampleDiffs.gitContext, look: look,
      options: DisplayOptions(increasesContrast: look.increasesContrast), size: Self.size,
      named: "single-column-\(look.name)", prepare: Self.showSingleColumn)
  }

  @Test(arguments: [Look.light, .dark])
  func singleColumnIsPicturedWithoutColor(look: Look) async throws {
    try Windows.picture(
      try await SampleDiffs.greeting(), context: SampleDiffs.gitContext, look: look,
      options: DisplayOptions(differentiatesWithoutColor: true), size: Self.size,
      named: "single-column-without-color-\(look.name)", prepare: Self.showSingleColumn)
  }

  @Test func singleColumnIsPicturedWithReducedTransparency() async throws {
    try Windows.picture(
      try await SampleDiffs.greeting(), context: SampleDiffs.gitContext, look: .light,
      options: DisplayOptions(reducesTransparency: true), size: Self.size,
      named: "single-column-reduced-transparency-light", prepare: Self.showSingleColumn)
  }

  @Test(arguments: [Look.light, .dark])
  func singleColumnIsPicturedInTheSmallestWindow(look: Look) async throws {
    let settings = UserSettings.private()
    settings.showsSingleColumn = true
    try Windows.picture(
      try await SampleDiffs.everyKindOfChange(), context: SessionContext(), look: look,
      settings: settings, size: nil, named: "single-column-smallest-\(look.name)"
    ) { controller in
      controller.presentation.jump(to: 4)
    }
  }

  @Test(arguments: [Look.light, .dark])
  func singleColumnIsPicturedWithWrappedLinesAndTheCurrentBlock(look: Look) async throws {
    let settings = UserSettings.private()
    settings.wrapsLines = true
    try Windows.picture(
      try await SampleDiffs.everyKindOfChange(longLines: true), context: SessionContext(),
      look: look, settings: settings, actsAsKey: true, size: CGSize(width: 900, height: 640),
      named: "single-column-wrapped-\(look.name)"
    ) { controller in
      controller.showSingleColumn(nil)
      if let column = controller.layout.columnPane {
        controller.window?.makeFirstResponder(column.documentView)
      }
      controller.presentation.jump(to: 5)
    }
  }

  @Test(arguments: [Look.light, .dark])
  func singleColumnIsPicturedWithCollapsedRuns(look: Look) async throws {
    try Windows.picture(
      try await SampleDiffs.manyChanges(), context: SessionContext(), look: look,
      named: "single-column-collapsed-\(look.name)", prepare: Self.showSingleColumn)
  }

  @Test(arguments: Look.all)
  func toolbarsShowTheChoiceOfTheArrangement(look: Look) async throws {
    let options = DisplayOptions(increasesContrast: look.increasesContrast)
    try Windows.picture(
      try await SampleDiffs.greeting(), context: SampleDiffs.gitContext, look: look,
      options: options, size: Self.size, named: "toolbar-arrangement-diff-\(look.name)",
      prepare: Self.showSingleColumn)
    try Windows.picture(
      try await SampleMerges.helloWorld(), context: SessionContext(), look: look,
      options: options, size: Self.size, named: "toolbar-arrangement-merge-\(look.name)")
  }

  private static let size = CGSize(width: 1100, height: 560)

  private static func showSingleColumn(_ controller: SessionWindowController) {
    controller.showSingleColumn(nil)
  }
}
