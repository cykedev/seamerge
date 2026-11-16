import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// Draws the pictures of a window that waits for the comparison of its files, for the visual
/// review: a comparison and a merge in every look, without color, with transparency reduced,
/// and at the least size.
@MainActor
@Suite(.serialized) struct PendingComparisonPicturesTests {
  private static let files = [
    Role.a: SessionFile(url: URL(filePath: "/tmp/old/Greeting.swift"), label: "Greeting.swift"),
    .b: SessionFile(url: URL(filePath: "/tmp/new/Greeting.swift"), label: "Greeting.swift"),
  ]

  private static let mergeFiles = [
    Role.base: SessionFile(url: URL(filePath: "/tmp/base/Settings.swift"), label: "Settings.swift"),
    .a: SessionFile(url: URL(filePath: "/tmp/theirs/Settings.swift"), label: "Settings.swift"),
    .b: SessionFile(url: URL(filePath: "/tmp/ours/Settings.swift"), label: "Settings.swift"),
  ]

  /// Draws the window that waits for the comparison of `files`, a comparison that never ends.
  private func picture(
    _ files: [Role: SessionFile], kind: Session.Kind, look: Look,
    options: DisplayOptions = DisplayOptions(), size: CGSize? = WindowMetrics.defaultContentSize,
    named name: String
  ) async throws {
    let (outcomes, continuation) = AsyncStream.makeStream(
      of: Result<Session, SessionLoadingError>.self)
    defer { continuation.finish() }
    let comparison = PendingComparison {
      var iterator = outcomes.makeAsyncIterator()
      return await iterator.next() ?? .failure(.comparisonFailed)
    }
    let empty = try await SessionWindowController.emptySession(
      of: files, kind: kind, mode: .windowDefault)
    var options = options
    options.increasesContrast = look.increasesContrast
    try Windows.picture(
      empty, context: SessionContext(), look: look, options: options, size: size, named: name,
      pendingComparison: comparison)
  }

  @Test(arguments: Look.all)
  func waitingComparisonIsPicturedInEveryLook(look: Look) async throws {
    try await picture(Self.files, kind: .diff, look: look, named: "pending-diff-\(look.name)")
  }

  @Test(arguments: Look.all)
  func waitingMergeIsPicturedInEveryLook(look: Look) async throws {
    try await picture(
      Self.mergeFiles, kind: .merge, look: look, named: "pending-merge-\(look.name)")
  }

  @Test func waitingComparisonIsPicturedWithoutColorAndWithoutTransparency() async throws {
    try await picture(
      Self.files, kind: .diff, look: .light,
      options: DisplayOptions(differentiatesWithoutColor: true, reducesTransparency: true),
      named: "pending-diff-without-color-and-transparency")
  }

  @Test func waitingMergeIsPicturedAtItsLeastSize() async throws {
    try await picture(
      Self.mergeFiles, kind: .merge, look: .dark, size: nil, named: "pending-merge-least-size")
  }
}
