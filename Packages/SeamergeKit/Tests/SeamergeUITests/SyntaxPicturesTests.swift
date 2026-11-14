import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// Draws the merge window with its code colored by its syntax, for the visual review: every
/// look, without color, and with the current block in the result being typed in.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct SyntaxPicturesTests {
  @Test(arguments: Look.all)
  func helloWorldIsPicturedWithSyntaxColorsInEveryLook(look: Look) async throws {
    try await Self.picture(
      look: look, options: DisplayOptions(increasesContrast: look.increasesContrast),
      named: "syntax-helloworld-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func helloWorldIsPicturedWithSyntaxColorsWithoutColor(look: Look) async throws {
    try await Self.picture(
      look: look, options: DisplayOptions(differentiatesWithoutColor: true),
      named: "syntax-helloworld-without-color-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func helloWorldIsPicturedWithSyntaxColorsAfterTyping(look: Look) async throws {
    try await Self.picture(look: look, named: "syntax-helloworld-typed-\(look.name)") {
      controller in
      controller.resolveAllWithB(nil)
      // A comment typed at the start of the result colors only its own line.
      try controller.type("// typed\n", over: 0..<0, with: .insertText)
    }
  }

  /// Draws the sample merge of P4Merge once every pane has its tokens, after `prepare`.
  private static func picture(
    look: Look, options: DisplayOptions = DisplayOptions(), named name: String,
    prepare: (SessionWindowController) throws -> Void = { _ in }
  ) async throws {
    let controller = SessionWindowController(
      session: try await SampleMerges.helloWorld(), context: SampleMerges.helloWorldContext,
      undoManager: UndoManager(), displayOptions: options, pasteboard: .withUniqueName(),
      workspace: WorkspaceRecorder(), prompts: PromptRecorder(), doneStyle: .standard,
      settings: .private(), window: SessionWindow())
    let window = try #require(controller.window)
    defer { window.close() }
    Rendering.prepare(window, size: WindowMetrics.defaultContentSize, appearance: look.appearance)
    controller.layout.placeDividers()
    controller.stateDidChange()
    await SyntaxFixture.lexing(of: controller)
    try prepare(controller)
    try Rendering.write(Rendering.bitmap(of: window), named: name)
  }
}
