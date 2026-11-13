import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Draws the pictures of deciding and editing in the merge window for the visual review: the
/// sample merge of P4Merge open and with its conflict resolved, lines typed by hand, toggles
/// switched in order, and the note of a removal in a preview, in every look.
@MainActor
@Suite(.serialized) struct DecisionPicturesTests {
  @Test(arguments: [false, true])
  func helloWorldIsPicturedOpenAndResolvedForTheComparisonWithP4Merge(resolved: Bool)
    async throws
  {
    let session = try await SampleMerges.helloWorld()
    try Windows.picture(
      session, context: SampleMerges.helloWorldContext, look: .light,
      options: DisplayOptions(reducesMotion: true),
      named: "p4merge-comparison-\(resolved ? "resolved" : "open")-light"
    ) { controller in
      guard resolved else { return }
      controller.perform(.useAThenB)
    }
  }

  @Test(arguments: Look.all)
  func handwrittenLinesArePicturedInEveryLook(look: Look) async throws {
    try await picture(look: look, named: "handwritten-\(look.name)") { controller in
      try typeHandwrittenLines(in: controller)
    }
  }

  @Test(arguments: Look.all)
  func togglesSwitchedInOrderArePicturedInEveryLook(look: Look) async throws {
    try await picture(look: look, named: "toggles-in-order-\(look.name)") { controller in
      let conflict = controller.presentation.navigation.firstOpenConflict
      controller.presentation.setCurrentBlock(conflict)
      controller.perform(.toggleSourceB)
      controller.perform(.toggleSourceA)
    }
  }

  @Test(arguments: Look.all)
  func removalNoteOfAPreviewIsPicturedInEveryLook(look: Look) async throws {
    let session = try await EditingFixture.nineBlocks()
    try Windows.picture(
      session, context: SessionContext(), look: look,
      options: DisplayOptions(increasesContrast: look.increasesContrast, reducesMotion: true),
      named: "removal-note-\(look.name)"
    ) { controller in
      controller.presentation.jump(to: 3)
    }
  }

  @Test func decisionsArePicturedWithoutColorWithReducedTransparencyAndSmallest() async throws {
    for (options, name, size) in [
      (
        DisplayOptions(differentiatesWithoutColor: true, reducesMotion: true), "without-color",
        Optional(WindowMetrics.defaultContentSize)
      ),
      (
        DisplayOptions(reducesTransparency: true, reducesMotion: true), "reduced-transparency",
        WindowMetrics.defaultContentSize
      ),
      (DisplayOptions(reducesMotion: true), "smallest", nil),
    ] {
      try await picture(
        look: .light, options: options, size: size, named: "decisions-\(name)-light"
      ) {
        controller in
        try typeHandwrittenLines(in: controller)
        controller.presentation.setCurrentBlock(1)
        controller.perform(.useAThenB)
      }
    }
  }

  /// Types two lines by hand into the first change of the sample merge, and changes a word of
  /// the line after them.
  private func typeHandwrittenLines(in controller: SessionWindowController) throws {
    let result = try controller.mergeResult
    let start = result.content.offset(ofRow: result.content.blocks[0].rows.lowerBound + 3)
    try controller.type(
      "// Typed by hand.\n// And this too.\n", over: start..<start, with: .insertText)
    controller.leaveTextMode()
  }

  /// Draws the sample merge of P4Merge in `look` after `prepare`.
  private func picture(
    look: Look, options: DisplayOptions? = nil, size: CGSize? = WindowMetrics.defaultContentSize,
    named name: String, prepare: @escaping (SessionWindowController) throws -> Void
  ) async throws {
    let session = try await SampleMerges.helloWorld()
    var failure: (any Error)?
    try Windows.picture(
      session, context: SampleMerges.helloWorldContext, look: look,
      options: options
        ?? DisplayOptions(increasesContrast: look.increasesContrast, reducesMotion: true),
      size: size,
      named: name
    ) { controller in
      do { try prepare(controller) } catch { failure = error }
    }
    if let failure { throw failure }
  }
}
