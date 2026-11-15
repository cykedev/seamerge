import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// A line too long to show whole in a window: the panes cut it, the result keeps all of it.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct LongLineTests {
  private static let longLine = (0..<10_000).map { "v\($0 % 10)" }.joined(separator: ",")

  @Test func savingAResultEditedInALongLineWritesAllOfTheLine() async throws {
    let session = try await SampleMerges.merge(
      base: "first\n" + Self.longLine + "\nlast\n",
      a: "first from A\n" + Self.longLine + "\nlast\n", b: "first\n" + Self.longLine + "\nlast\n")
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "LongLineTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer {
      #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) }
    }
    let resultURL = folder.appending(path: "result.txt")
    let controller = try Windows.controller(
      for: session, context: SessionContext(resultURL: resultURL))
    defer { controller.window?.close() }
    let start = ("first from A\n" as NSString).length
    try #require(
      (Self.longLine as NSString).length > PaneView.maximumShownLineLength,
      "the line is cut")

    try controller.type("typed ", over: start..<start, with: .insertText)
    #expect(await controller.save())

    #expect(
      try String(contentsOf: resultURL, encoding: .utf8)
        == "first from A\ntyped " + Self.longLine + "\nlast\n")
  }

  @Test(arguments: [Look.light, .dark])
  func longLineIsPicturedEndingWithAnEllipsis(look: Look) async throws {
    let words = (0..<3_000).map { "word\($0 % 97)" }.joined(separator: " ")
    let session = try await SampleDiffs.diff(
      old: "intro\n" + words + "\nend\n", new: "intro changed\n" + words + "\nend\n",
      label: "minified.js")
    let settings = UserSettings.private()
    settings.wrapsLines = true
    try Windows.picture(
      session, context: SessionContext(), look: look, settings: settings,
      named: "long-line-\(look.name)"
    ) { controller in
      for pane in Windows.panes(of: controller) {
        let text = pane.documentView
        text.scroll(CGPoint(x: 0, y: max(text.frame.height - text.visibleRect.height, 0)))
      }
    }
  }
}
