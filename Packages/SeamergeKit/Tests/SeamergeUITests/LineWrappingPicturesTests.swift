import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Draws the pictures of wrapped lines for the visual review: a merge and a comparison of two
/// files with long lines, in every look, without color, with reduced transparency, and in the
/// smallest window.
@MainActor
@Suite(.serialized) struct LineWrappingPicturesTests {
  @Test(arguments: Look.all)
  func mergeIsPicturedWithWrappedLinesInEveryLook(look: Look) async throws {
    try Windows.picture(
      try await LineWrappingWindowTests.merge(), context: SessionContext(), look: look,
      options: DisplayOptions(increasesContrast: look.increasesContrast),
      settings: Self.wrappingSettings(), named: "wrapped-merge-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func comparisonIsPicturedWithWrappedLines(look: Look) async throws {
    try Windows.picture(
      try await Self.diff(), context: SessionContext(), look: look,
      settings: Self.wrappingSettings(), named: "wrapped-diff-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func mergeIsPicturedWithWrappedLinesInTheSmallestWindow(look: Look) async throws {
    try Windows.picture(
      try await LineWrappingWindowTests.merge(), context: SessionContext(), look: look,
      settings: Self.wrappingSettings(), size: nil, named: "wrapped-merge-smallest-\(look.name)")
  }

  @Test func mergeIsPicturedWithWrappedLinesWithoutColorAndTransparency() async throws {
    try Windows.picture(
      try await LineWrappingWindowTests.merge(), context: SessionContext(), look: .light,
      options: DisplayOptions(differentiatesWithoutColor: true, reducesTransparency: true),
      settings: Self.wrappingSettings(), named: "wrapped-merge-without-color-light")
  }

  /// Settings in which new windows wrap lines.
  static func wrappingSettings() -> UserSettings {
    let settings = UserSettings.private()
    settings.wrapsLines = true
    return settings
  }

  /// A comparison whose newer file makes an indented line longer and adds a long comment.
  static func diff() async throws -> Session {
    let old = """
      struct Greeting {
        let name: String

        func text() -> String {
          "Hello, \\(name)!"
        }
      }

      """
    let new = """
      struct Greeting {
        let name: String

        /// The greeting as the window shows it, with the name of the person and a long sentence that runs on.
        func text() -> String {
          "Hello, \\(name)! It is good to see you again, and we hope that the day treats you well."
        }
      }

      """
    return try await SampleDiffs.diff(old: old, new: new)
  }
}
