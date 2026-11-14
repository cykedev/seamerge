import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Draws the pictures of a merge whose panes connect their changes with bands, with cases 1 to 7
/// of the test data at the top of the example: in every look, beside the grid, without color,
/// with reduced transparency, in the smallest window, without the base, with two conflicts
/// resolved, and with wrapped lines.
@MainActor
@Suite(.serialized) struct ConnectedMergePicturesTests {
  @Test(arguments: Look.all)
  func connectedMergeIsPicturedInEveryLook(look: Look) async throws {
    try Windows.picture(
      try await SampleMerges.example(), context: SessionContext(), look: look,
      options: DisplayOptions(increasesContrast: look.increasesContrast),
      settings: Self.settings(aligned: false), size: Self.size,
      named: "merge-connected-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func alignedMergeIsPicturedBesideIt(look: Look) async throws {
    try Windows.picture(
      try await SampleMerges.example(), context: SessionContext(), look: look,
      settings: Self.settings(aligned: true), size: Self.size,
      named: "merge-aligned-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func connectedMergeIsPicturedWithoutColor(look: Look) async throws {
    try Windows.picture(
      try await SampleMerges.example(), context: SessionContext(), look: look,
      options: DisplayOptions(differentiatesWithoutColor: true),
      settings: Self.settings(aligned: false), size: Self.size,
      named: "merge-connected-without-color-\(look.name)")
  }

  @Test func connectedMergeIsPicturedWithReducedTransparency() async throws {
    try Windows.picture(
      try await SampleMerges.example(), context: SessionContext(), look: .light,
      options: DisplayOptions(reducesTransparency: true), settings: Self.settings(aligned: false),
      size: Self.size, named: "merge-connected-reduced-transparency-light")
  }

  @Test(arguments: [Look.light, .dark])
  func connectedMergeIsPicturedInTheSmallestWindow(look: Look) async throws {
    try Windows.picture(
      try await SampleMerges.example(), context: SessionContext(), look: look,
      settings: Self.settings(aligned: false), size: nil,
      named: "merge-connected-smallest-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func connectedMergeIsPicturedWithoutTheBase(look: Look) async throws {
    try Windows.picture(
      try await SampleMerges.example(), context: SessionContext(), look: look,
      settings: Self.settings(aligned: false), size: Self.size,
      named: "merge-connected-without-base-\(look.name)"
    ) { controller in
      controller.toggleBase(nil)
    }
  }

  @Test(arguments: [Look.light, .dark])
  func connectedMergeIsPicturedWithTwoConflictsResolved(look: Look) async throws {
    try Windows.picture(
      try await SampleMerges.example(), context: SessionContext(), look: look,
      settings: Self.settings(aligned: false), actsAsKey: true, size: Self.size,
      named: "merge-connected-resolved-\(look.name)"
    ) { controller in
      controller.perform(.useA)
      controller.perform(.useAThenB)
    }
  }

  @Test(arguments: [Look.light, .dark])
  func connectedMergeIsPicturedWithWrappedLines(look: Look) async throws {
    let settings = Self.settings(aligned: false)
    settings.wrapsLines = true
    try Windows.picture(
      try await SampleMerges.example(), context: SessionContext(), look: look,
      settings: settings, size: Self.size, named: "merge-connected-wrapped-\(look.name)")
  }

  /// Settings in which a new window lines up its lines, or connects its changes with bands.
  private static func settings(aligned: Bool) -> UserSettings {
    let settings = UserSettings.private()
    settings.alignsLines = aligned
    return settings
  }

  /// The size of the pictures, in which cases 1 to 7 stand in the panes side by side.
  private static let size = CGSize(width: 1440, height: 1200)
}
