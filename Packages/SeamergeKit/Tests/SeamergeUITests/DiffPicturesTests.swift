import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Draws the pictures of the window of a comparison for the visual review: an insertion, a
/// change and a removal in every look, without color, in the smallest window, with the sides
/// swapped, with collapsed runs, the toolbar at a change in the middle, and a file that only
/// changed its whitespace.
@MainActor
@Suite(.serialized) struct DiffPicturesTests {
  @Test(arguments: Look.all)
  func comparisonIsPicturedInEveryLook(look: Look) async throws {
    try Windows.picture(
      try await SampleDiffs.greeting(), context: SampleDiffs.gitContext, look: look,
      options: DisplayOptions(increasesContrast: look.increasesContrast),
      size: Self.size, named: "diff-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func comparisonIsPicturedWithoutColor(look: Look) async throws {
    try Windows.picture(
      try await SampleDiffs.greeting(), context: SampleDiffs.gitContext, look: look,
      options: DisplayOptions(differentiatesWithoutColor: true), size: Self.size,
      named: "diff-without-color-\(look.name)")
  }

  @Test func comparisonIsPicturedWithReducedTransparency() async throws {
    try Windows.picture(
      try await SampleDiffs.greeting(), context: SampleDiffs.gitContext, look: .light,
      options: DisplayOptions(reducesTransparency: true), size: Self.size,
      named: "diff-reduced-transparency-light")
  }

  @Test func comparisonIsPicturedInTheSmallestWindow() async throws {
    try Windows.picture(
      try await SampleDiffs.greeting(), context: SampleDiffs.gitContext, look: .light, size: nil,
      named: "diff-smallest-light")
  }

  @Test(arguments: [Look.light, .dark])
  func comparisonIsPicturedWithItsSidesSwapped(look: Look) async throws {
    try Windows.picture(
      try await SampleDiffs.greeting(), context: SampleDiffs.gitContext, look: look,
      size: Self.size, named: "diff-swapped-\(look.name)"
    ) { controller in
      controller.swapSides(nil)
    }
  }

  @Test(arguments: [Look.light, .dark])
  func comparisonIsPicturedWithCollapsedRuns(look: Look) async throws {
    try Windows.picture(
      try await SampleDiffs.manyChanges(), context: SessionContext(), look: look,
      named: "diff-collapsed-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func toolbarIsPicturedAtTheFourthOfTwelveChanges(look: Look) async throws {
    let session = try await SampleDiffs.manyChanges()
    try #require(SessionChanges(session: session).blocks.count == 12)
    try Windows.picture(
      session, context: SessionContext(), look: look, actsAsKey: true,
      named: "diff-change-4-of-12-\(look.name)"
    ) { controller in
      controller.presentation.jump(to: 3)
    }
  }

  @Test func reformattedFileIsPicturedWithAllWhitespaceIgnored() async throws {
    let session = try await SampleDiffs.diff(
      old: SampleDiffs.reformattedOld, new: SampleDiffs.reformattedNew,
      label: "Sources/Area.swift", mode: .ignoreAllWhitespace)
    try Windows.picture(
      session, context: SessionContext(), look: .light, size: Self.size,
      named: "diff-no-changes-light")
  }

  /// The size of the pictures of the short sample, which shows all of it.
  private static let size = CGSize(width: 1280, height: 560)
}
