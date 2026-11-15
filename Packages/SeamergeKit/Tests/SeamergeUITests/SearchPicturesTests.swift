import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Pictures of the find bar of a window for review: in a merge, in a comparison, in the
/// smallest window, with the field for replacing, and the strokes of the matches in the overview
/// bars.
///
/// The finder keeps its search text on the find pasteboard of the system, which every app
/// shares; each test puts back what it held, whether the test passes or not.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SearchPicturesTests {
  @Test(arguments: Look.all)
  func findBarInAMerge(look: Look) async throws {
    try await FindPasteboard.preserving {
      try await picture(
        try await SampleMerges.example(), look: look,
        options: DisplayOptions(increasesContrast: look.increasesContrast),
        named: "search-merge-\(look.name)", searchingFor: "discount", matchCount: 15)
    }
  }

  @Test(arguments: [Look.light, .dark])
  func findBarInAComparison(look: Look) async throws {
    try await FindPasteboard.preserving {
      try await picture(
        try await SampleDiffs.greeting(), look: look, named: "search-diff-\(look.name)",
        searchingFor: "name", matchCount: nil)
    }
  }

  @Test(arguments: [Look.light, .dark])
  func findAndReplaceInTheSmallestWindow(look: Look) async throws {
    try await FindPasteboard.preserving {
      try await picture(
        try await SampleMerges.example(), look: look, size: nil,
        named: "search-replace-smallest-\(look.name)", searchingFor: "discount",
        matchCount: nil, replacing: true)
    }
  }

  @Test func findBarWithoutColorAndWithReducedTransparency() async throws {
    try await FindPasteboard.preserving {
      try await picture(
        try await SampleMerges.example(), look: .dark,
        options: DisplayOptions(differentiatesWithoutColor: true, reducesTransparency: true),
        named: "search-merge-without-color-reduced-transparency-dark", searchingFor: "discount",
        matchCount: nil)
    }
  }

  /// Draws the window of `session` at `size`, or at its least size for `nil`, with the find bar
  /// open on `needle`, after `matchCount` matches if given, else after the first change of the
  /// matches; with `replacing`, through Find and Replace.
  private func picture(
    _ session: Session, look: Look, options: DisplayOptions = DisplayOptions(),
    size: CGSize? = WindowMetrics.defaultContentSize, named name: String,
    searchingFor needle: String, matchCount: Int?, replacing: Bool = false
  ) async throws {
    let controller = SessionWindowController(
      session: session, context: SessionContext(), undoManager: UndoManager(),
      displayOptions: options, pasteboard: .withUniqueName(), workspace: WorkspaceRecorder(),
      prompts: PromptRecorder(), doneStyle: .standard, settings: .private(),
      window: KeySessionWindow())
    let window = try #require(controller.window)
    defer { window.close() }
    Rendering.prepare(window, size: size ?? window.contentMinSize, appearance: look.appearance)
    controller.layout.placeDividers()
    controller.stateDidChange()
    let driver = SearchDriver(controller)
    #expect(try driver.send(replacing ? .findAndReplace : .find))
    try driver.type(needle)
    if let matchCount {
      await driver.waitForMatches(count: matchCount)
    } else {
      await driver.waitForMatches { !driver.search.matches.isEmpty }
    }
    if replacing {
      try driver.typeReplacement("rebate")
    }
    window.contentView?.layoutSubtreeIfNeeded()
    try Rendering.write(Rendering.bitmap(of: window), named: name)
  }
}
