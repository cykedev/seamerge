import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Draws the pictures of the seam with the buttons that copy a change: lined-up lines and
/// connected sides, with one and with two sides that may be written, in every look, without
/// color, with reduced transparency and in the smallest window, and the single column, which
/// has no buttons.
@MainActor
@Suite(.serialized) struct CopyPicturesTests {
  @Test(arguments: Look.all)
  func seamIsPicturedInEveryLook(look: Look) async throws {
    for (aligns, context, name) in Self.cases {
      try Windows.picture(
        try await WritableComparisons.greeting(), context: context, look: look,
        options: DisplayOptions(increasesContrast: look.increasesContrast),
        settings: Self.settings(aligningLines: aligns), actsAsKey: true, size: Self.size,
        named: "copy-\(name)-\(look.name)", prepare: Self.makeTheChangeCurrent)
    }
  }

  @Test(arguments: [Look.light, .dark])
  func seamIsPicturedWithoutColor(look: Look) async throws {
    for (aligns, context, name) in Self.cases {
      try Windows.picture(
        try await WritableComparisons.greeting(), context: context, look: look,
        options: DisplayOptions(differentiatesWithoutColor: true),
        settings: Self.settings(aligningLines: aligns), actsAsKey: true, size: Self.size,
        named: "copy-\(name)-without-color-\(look.name)", prepare: Self.makeTheChangeCurrent)
    }
  }

  @Test func seamIsPicturedWithReducedTransparency() async throws {
    for (aligns, context, name) in Self.cases {
      try Windows.picture(
        try await WritableComparisons.greeting(), context: context, look: .light,
        options: DisplayOptions(reducesTransparency: true),
        settings: Self.settings(aligningLines: aligns), actsAsKey: true, size: Self.size,
        named: "copy-\(name)-reduced-transparency-light", prepare: Self.makeTheChangeCurrent)
    }
  }

  @Test(arguments: [Look.light, .dark])
  func seamIsPicturedInTheSmallestWindow(look: Look) async throws {
    for (aligns, name) in [(true, "aligned"), (false, "connected")] {
      try Windows.picture(
        try await WritableComparisons.everyKindOfChange(), context: SessionContext(),
        look: look, settings: Self.settings(aligningLines: aligns), size: nil,
        named: "copy-\(name)-both-smallest-\(look.name)"
      ) { controller in
        controller.presentation.jump(to: 4)
      }
    }
  }

  @Test(arguments: [Look.light, .dark])
  func binsArePicturedAtTheStartOfTheRowsAndOneLineApart(look: Look) async throws {
    for (context, name) in [(SampleDiffs.gitContext, "one"), (SessionContext(), "both")] {
      try Windows.picture(
        try await WritableComparisons.denseInsertions(), context: context, look: look,
        settings: Self.settings(aligningLines: false), actsAsKey: true,
        size: CGSize(width: 1000, height: 420), named: "copy-connected-bins-\(name)-\(look.name)",
        prepare: Self.makeTheChangeCurrent)
    }
  }

  @Test(arguments: [Look.light, .dark])
  func singleColumnIsPicturedWithoutButtons(look: Look) async throws {
    let settings = UserSettings.private()
    settings.showsSingleColumn = true
    try Windows.picture(
      try await WritableComparisons.greeting(), context: SessionContext(), look: look,
      settings: settings, size: Self.size, named: "copy-single-column-\(look.name)",
      prepare: Self.makeTheChangeCurrent)
  }

  /// Lined-up lines and connected sides, each with the working copy of Git alone writable and
  /// with two files the user chose.
  private static let cases: [(Bool, SessionContext, String)] = [
    (true, SampleDiffs.gitContext, "aligned-one"), (true, SessionContext(), "aligned-both"),
    (false, SampleDiffs.gitContext, "connected-one"), (false, SessionContext(), "connected-both"),
  ]

  private static func settings(aligningLines: Bool) -> UserSettings {
    let settings = UserSettings.private()
    settings.alignsLines = aligningLines
    return settings
  }

  private static func makeTheChangeCurrent(_ controller: SessionWindowController) {
    controller.presentation.jump(to: 1)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
  }

  private static let size = CGSize(width: 1100, height: 520)
}
