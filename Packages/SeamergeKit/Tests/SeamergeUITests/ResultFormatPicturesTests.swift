import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// Draws the result header with the pop-up menus of the encoding and the line endings and the
/// line about mixed line endings for the visual review: in every look, without color, without
/// transparency and at the least size.
@MainActor
@Suite(.serialized) struct ResultFormatPicturesTests {
  /// The sample merge of P4Merge, with B ending its lines in CRLF and LF.
  private func mixedMerge() async throws -> Session {
    let lines = SampleMerges.helloWorldB.split(separator: "\n", omittingEmptySubsequences: false)
    let mixed = lines.enumerated().map {
      $0.offset.isMultiple(of: 3) ? $0.element + "\r" : $0.element
    }
    .joined(separator: "\n")
    return try await Session.merge(
      base: SourceFile(bytes: Data(SampleMerges.helloWorldBase.utf8), label: "HelloWorld0.java"),
      a: SourceFile(bytes: Data(SampleMerges.helloWorldA.utf8), label: "HelloWorld1.java"),
      b: SourceFile(bytes: Data(mixed.utf8), label: "HelloWorld2.java"),
      options: ComparisonOptions(mode: .windowDefault))
  }

  @Test(arguments: Look.all)
  func resultHeaderIsPicturedInEveryLook(look: Look) async throws {
    try Windows.picture(
      try await mixedMerge(), context: SampleMerges.helloWorldContext, look: look,
      options: DisplayOptions(increasesContrast: look.increasesContrast), actsAsKey: true,
      named: "result-format-\(look.name)")
  }

  @Test func resultHeaderIsPicturedWithoutColorWithoutTransparencyAndSmallest() async throws {
    let session = try await mixedMerge()
    let context = SampleMerges.helloWorldContext
    try Windows.picture(
      session, context: context, look: .light,
      options: DisplayOptions(differentiatesWithoutColor: true),
      named: "result-format-without-color-light")
    try Windows.picture(
      session, context: context, look: .light,
      options: DisplayOptions(reducesTransparency: true),
      named: "result-format-reduced-transparency-light")
    try Windows.picture(
      session, context: context, look: .light, size: nil, named: "result-format-smallest-light")
  }
}
