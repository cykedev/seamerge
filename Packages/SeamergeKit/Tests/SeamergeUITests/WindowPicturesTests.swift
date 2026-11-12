import AppKit
import MergeModel
import SwiftUI
import Testing

@testable import SeamergeUI

/// Draws the pictures of the merge window for the visual review: every merge scenario of the
/// test repositories, the sample merge of P4Merge, touching blocks, and every look.
@MainActor
@Suite(.serialized) struct WindowPicturesTests {
  @Test(arguments: Scenario.merges, [Look.light, .dark])
  func scenarioIsPictured(scenario: Scenario, look: Look) async throws {
    let (session, context) = try await scenario.load()
    try picture(
      session, context: context, look: look, named: "scenario-\(scenario.name)-\(look.name)")
  }

  @Test func helloWorldIsPicturedForTheComparisonWithP4Merge() async throws {
    let session = try await SampleMerges.helloWorld()
    try picture(
      session, context: SampleMerges.helloWorldContext, look: .light,
      named: "p4merge-comparison-light")
  }

  @Test(arguments: Look.all)
  func helloWorldIsPicturedInEveryLook(look: Look) async throws {
    let session = try await SampleMerges.helloWorld()
    try picture(
      session, context: SampleMerges.helloWorldContext, look: look,
      options: DisplayOptions(increasesContrast: look.increasesContrast),
      named: "helloworld-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func helloWorldIsPicturedWithoutColor(look: Look) async throws {
    let session = try await SampleMerges.helloWorld()
    try picture(
      session, context: SampleMerges.helloWorldContext, look: look,
      options: DisplayOptions(differentiatesWithoutColor: true),
      named: "helloworld-without-color-\(look.name)")
  }

  @Test func smallestWindowIsPictured() async throws {
    let session = try await SampleMerges.helloWorld()
    try picture(
      session, context: SampleMerges.helloWorldContext, look: .light, size: nil,
      named: "helloworld-smallest-light")
  }

  @Test func noticeThatGitNoLongerWaitsIsPictured() async throws {
    let (session, context) = try await Scenario.merges[0].load()
    try picture(session, context: context, look: .light, named: "notice-light") { controller in
      controller.callerDisconnected()
    }
  }

  @Test(
    arguments: SampleMerges.TouchingBlocks.allCases,
    [(Look.light, false), (.dark, false), (.light, true)])
  func touchingBlocksArePictured(
    blocks: SampleMerges.TouchingBlocks, setting: (look: Look, withoutColor: Bool)
  ) async throws {
    let session = try await blocks.session()
    let name =
      "touching-\(blocks.rawValue)-\(setting.withoutColor ? "without-color-" : "")"
      + setting.look.name
    try picture(
      session, context: SessionContext(), look: setting.look,
      options: DisplayOptions(differentiatesWithoutColor: setting.withoutColor),
      size: CGSize(width: 1280, height: 600), named: name)
    try picture(
      session, context: SessionContext(), look: setting.look,
      options: DisplayOptions(differentiatesWithoutColor: setting.withoutColor),
      size: CGSize(width: 1280, height: 600), named: "\(name)-second-current"
    ) { controller in
      for pane in controller.layout.sourcePanes.map(\.pane) + [controller.layout.resultPane] {
        pane.currentBlock = 1
      }
    }
  }

  @Test(arguments: [Look.light, .dark])
  func detailsOfASideArePictured(look: Look) async throws {
    let scenario = try #require(Scenario.merges.first { $0.name == "rebase" })
    let (session, context) = try await scenario.load()
    let header = SideHeader(role: .a, session: session, context: context)
    let view = NSHostingView(rootView: SideDetailsView(header: header, theme: .init()))
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: view.fittingSize), styleMask: [.borderless],
      backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    window.contentView = view
    window.backgroundColor = .windowBackgroundColor
    defer { window.close() }
    Rendering.prepare(window, size: view.fittingSize, appearance: look.appearance)
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try Rendering.write(bitmap, named: "details-\(look.name)")
  }

  /// Draws the window of `session` at `size`, or at its least size for `nil`, after `prepare`.
  private func picture(
    _ session: Session, context: SessionContext, look: Look,
    options: DisplayOptions = DisplayOptions(),
    size: CGSize? = WindowMetrics.defaultContentSize, named name: String,
    prepare: (SessionWindowController) -> Void = { _ in }
  ) throws {
    let controller = SessionWindowController(
      session: session, context: context, undoManager: UndoManager(), displayOptions: options,
      pasteboard: .withUniqueName(), workspace: WorkspaceRecorder(),
      prompts: PromptRecorder())
    let window = try #require(controller.window)
    defer { window.close() }
    Rendering.prepare(window, size: size ?? window.contentMinSize, appearance: look.appearance)
    controller.layout.placeDividers()
    prepare(controller)
    try Rendering.write(Rendering.bitmap(of: window), named: name)
  }
}
