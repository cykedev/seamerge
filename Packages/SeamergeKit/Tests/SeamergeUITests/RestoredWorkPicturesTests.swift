import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// Draws the pictures of a merge that put back its earlier work, with the note in the subtitle,
/// and of the sheet before closing a merge that a command waits for, which says that the work
/// is kept.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct RestoredWorkPicturesTests {
  /// Draws the sample merge with the work of an earlier window put back, in `look` with
  /// `options` at `size`.
  private static func picture(
    look: Look, options: DisplayOptions = DisplayOptions(),
    size: CGSize? = WindowMetrics.defaultContentSize, named name: String
  ) async throws {
    let session = try await SampleMerges.helloWorld()
    let context = SampleMerges.helloWorldContext
    let work = WorkFolder()
    let earlier = try Windows.controller(for: session, context: context, workKeeper: work.keeper())
    for _ in 0..<2 {
      earlier.presentation.setCurrentBlock(earlier.presentation.navigation.firstOpenConflict)
      earlier.perform(.useB)
      earlier.endEvent()
    }
    earlier.close()
    await earlier.workKeeper?.lastOperation?.value
    let earlierWork = await MergeWorkKeeper.earlierWork(of: session.inputs, in: work.store)
    #expect(earlierWork.work != nil)

    let keeper = work.keeper()
    try Windows.picture(
      session, context: context, look: look, options: options, size: size, named: name,
      workKeeper: keeper
    ) { controller in
      controller.restore(earlierWork)
      #expect(controller.window?.subtitle.contains("Earlier work restored") == true)
    }
    await keeper.lastOperation?.value
  }

  @Test(arguments: Look.all)
  func restoredWorkIsPicturedInEveryLook(look: Look) async throws {
    try await Self.picture(
      look: look, options: DisplayOptions(increasesContrast: look.increasesContrast),
      named: "restored-work-\(look.name)")
  }

  @Test func restoredWorkIsPicturedWithoutColor() async throws {
    try await Self.picture(
      look: .light, options: DisplayOptions(differentiatesWithoutColor: true),
      named: "restored-work-without-color-light")
  }

  @Test func restoredWorkIsPicturedWithReducedTransparency() async throws {
    try await Self.picture(
      look: .light, options: DisplayOptions(reducesTransparency: true),
      named: "restored-work-reduced-transparency-light")
  }

  @Test func restoredWorkIsPicturedInTheSmallestWindow() async throws {
    try await Self.picture(look: .light, size: nil, named: "restored-work-smallest-light")
  }

  /// The sheet draws in the colors of the system, which increased contrast of the app leaves
  /// alone.
  @Test(arguments: [Look.light, .dark])
  func sheetBeforeClosingSaysThatTheWorkIsKept(look: Look) throws {
    for (caller, suffix) in [
      (WaitingCaller.git, "git"), (.commandLine, "command-line"), (nil, "own-files"),
    ] {
      let alert = SessionSheets.closingAlert(
        "HelloWorld.java", openConflictCount: 2, caller: caller)
      try Rendering.write(
        try Rendering.bitmap(of: alert, in: look), named: "closing-sheet-\(suffix)-\(look.name)")
      #expect(
        alert.informativeText.hasSuffix(
          "Your work in this window is kept until you finish this merge."))
      #expect(alert.buttons.map(\.title) == ["Save", "Don’t Save", "Cancel"])
    }
  }
}
