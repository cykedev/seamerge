import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Draws the pictures of a comparison whose panes connect their changes with bands: an
/// insertion, a change and a removal in every look, without color, with reduced transparency, in
/// the smallest window, with wrapped lines, with a removal as the current block, and many changes
/// with collapsed runs.
@MainActor
@Suite(.serialized) struct ConnectedPicturesTests {
  @Test(arguments: Look.all)
  func connectedComparisonIsPicturedInEveryLook(look: Look) async throws {
    try Windows.picture(
      try await SampleDiffs.greeting(), context: SampleDiffs.gitContext, look: look,
      options: DisplayOptions(increasesContrast: look.increasesContrast),
      settings: Self.connectedSettings(), size: Self.size, named: "connected-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func connectedComparisonIsPicturedWithoutColor(look: Look) async throws {
    try Windows.picture(
      try await SampleDiffs.greeting(), context: SampleDiffs.gitContext, look: look,
      options: DisplayOptions(differentiatesWithoutColor: true),
      settings: Self.connectedSettings(), size: Self.size,
      named: "connected-without-color-\(look.name)")
  }

  @Test func connectedComparisonIsPicturedWithReducedTransparency() async throws {
    try Windows.picture(
      try await SampleDiffs.greeting(), context: SampleDiffs.gitContext, look: .light,
      options: DisplayOptions(reducesTransparency: true), settings: Self.connectedSettings(),
      size: Self.size, named: "connected-reduced-transparency-light")
  }

  @Test(arguments: [Look.light, .dark])
  func connectedComparisonIsPicturedInTheSmallestWindow(look: Look) async throws {
    try Windows.picture(
      try await SampleDiffs.everyKindOfChange(), context: SessionContext(), look: look,
      settings: Self.connectedSettings(), size: nil, named: "connected-smallest-\(look.name)"
    ) { controller in
      controller.presentation.jump(to: 4)
    }
  }

  @Test(arguments: [Look.light, .dark])
  func connectedComparisonIsPicturedWithWrappedLines(look: Look) async throws {
    let settings = Self.connectedSettings()
    settings.wrapsLines = true
    try Windows.picture(
      try await SampleDiffs.everyKindOfChange(longLines: true), context: SessionContext(),
      look: look, settings: settings, size: CGSize(width: 1100, height: 640),
      named: "connected-wrapped-\(look.name)"
    ) { controller in
      controller.presentation.jump(to: 3)
    }
  }

  @Test(arguments: [Look.light, .dark])
  func removalIsPicturedAsTheCurrentBlock(look: Look) async throws {
    try Windows.picture(
      try await SampleDiffs.everyKindOfChange(), context: SessionContext(), look: look,
      settings: Self.connectedSettings(), actsAsKey: true, size: Self.size,
      named: "connected-removal-current-\(look.name)"
    ) { controller in
      controller.presentation.jump(to: 3)
    }
  }

  @Test(arguments: [Look.light, .dark])
  func connectedComparisonIsPicturedWithCollapsedRuns(look: Look) async throws {
    try Windows.picture(
      try await SampleDiffs.manyChanges(), context: SessionContext(), look: look,
      settings: Self.connectedSettings(), named: "connected-collapsed-\(look.name)")
  }

  /// Settings in which a new comparison connects its changes rather than lining up its lines.
  private static func connectedSettings() -> UserSettings {
    let settings = UserSettings.private()
    settings.alignsLines = false
    return settings
  }

  /// The size of the pictures of the short sample, which shows all of it.
  private static let size = CGSize(width: 1280, height: 560)
}
