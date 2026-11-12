import AppKit
import MergeModel
import PaneKit
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
    try Windows.picture(
      session, context: context, look: look, named: "scenario-\(scenario.name)-\(look.name)")
  }

  @Test func helloWorldIsPicturedForTheComparisonWithP4Merge() async throws {
    let session = try await SampleMerges.helloWorld()
    try Windows.picture(
      session, context: SampleMerges.helloWorldContext, look: .light,
      named: "p4merge-comparison-light")
  }

  @Test(arguments: Look.all)
  func helloWorldIsPicturedInEveryLook(look: Look) async throws {
    let session = try await SampleMerges.helloWorld()
    try Windows.picture(
      session, context: SampleMerges.helloWorldContext, look: look,
      options: DisplayOptions(increasesContrast: look.increasesContrast),
      named: "helloworld-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func helloWorldIsPicturedWithoutColor(look: Look) async throws {
    let session = try await SampleMerges.helloWorld()
    try Windows.picture(
      session, context: SampleMerges.helloWorldContext, look: look,
      options: DisplayOptions(differentiatesWithoutColor: true),
      named: "helloworld-without-color-\(look.name)")
  }

  @Test(
    arguments: [
      (SessionToolbar.DoneStyle.word, false), (.word, true), (.checkmark, false),
      (.checkmark, true),
    ], [Look.light, .dark])
  func toolbarIsPicturedWithEitherDoneButton(
    variant: (style: SessionToolbar.DoneStyle, resolved: Bool), look: Look
  ) async throws {
    let (style, resolved) = variant
    let session = try await SampleMerges.helloWorld()
    let name =
      "toolbar-done-\(style == .word ? "word" : "checkmark")-\(resolved ? "resolved" : "open")-"
      + look.name
    try Windows.picture(
      session, context: SampleMerges.helloWorldContext, look: look, doneStyle: style,
      actsAsKey: true, named: name
    ) { controller in
      if resolved {
        controller.resolveOpenConflicts(with: [.a])
      }
    }
  }

  @Test(arguments: Look.all)
  func toolbarIsPicturedInEveryLook(look: Look) async throws {
    let session = try await SampleMerges.helloWorld()
    try Windows.picture(
      session, context: SampleMerges.helloWorldContext, look: look,
      options: DisplayOptions(increasesContrast: look.increasesContrast), actsAsKey: true,
      named: "toolbar-\(look.name)")
  }

  @Test func toolbarIsPicturedWhileComparing() async throws {
    let session = try await SampleMerges.helloWorld()
    try Windows.picture(
      session, context: SampleMerges.helloWorldContext, look: .light,
      named: "toolbar-comparing-light"
    ) { controller in
      controller.showsComparisonProgress = true
      controller.stateDidChange()
    }
  }

  @Test(arguments: [Look.light, .dark], [true, false])
  func currentBlockIsPicturedWithAndWithoutFocus(look: Look, hasFocus: Bool) async throws {
    let session = try await SampleMerges.manyBlocks()
    try Windows.picture(
      session, context: SessionContext(), look: look,
      options: DisplayOptions(reducesMotion: true), actsAsKey: true,
      size: CGSize(width: 1280, height: 600),
      named: "current-block-\(hasFocus ? "focus" : "no-focus")-\(look.name)"
    ) { controller in
      controller.presentation.jump(to: 6)
      if !hasFocus {
        controller.window?.makeFirstResponder(nil)
      }
    }
  }

  @Test(arguments: [Look.light, .dark])
  func currentBlockIsPicturedInTextMode(look: Look) async throws {
    let session = try await SampleMerges.manyBlocks()
    try Windows.picture(
      session, context: SessionContext(), look: look,
      options: DisplayOptions(reducesMotion: true), actsAsKey: true,
      size: CGSize(width: 1280, height: 600), named: "current-block-text-mode-\(look.name)"
    ) { controller in
      controller.presentation.jump(to: 6)
      controller.enterTextMode()
    }
  }

  @Test func baseHiddenIsPictured() async throws {
    let session = try await SampleMerges.helloWorld()
    try Windows.picture(
      session, context: SampleMerges.helloWorldContext, look: .light, named: "base-hidden-light"
    ) { controller in
      controller.toggleBase(nil)
    }
  }

  @Test func contextMenusAreWrittenDown() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
    let presentation = controller.presentation
    let conflict = try #require(presentation.navigation.firstOpenConflict)
    let change = try #require(presentation.changes.blocks.indices.first { $0 != conflict })
    presentation.setCurrentBlock(0)
    var lines: [String] = []
    for pane in Windows.panes(of: controller) {
      let name = pane.accessibilityLabel() ?? ""
      let places: [(String, PaneHit)] = [
        ("changed block", PaneHit(row: pane.content.blocks[change].rows.lowerBound, block: change)),
        (
          "open conflict",
          PaneHit(row: pane.content.blocks[conflict].rows.lowerBound, block: conflict)
        ),
        ("unchanged text", PaneHit(row: pane.content.lineNumbers.count - 1, block: nil)),
      ]
      for (place, hit) in places {
        presentation.setCurrentBlock(0)
        let menu = try #require(presentation.pane(pane, menuFor: hit))
        lines.append(
          "\(name), \(place): \(Self.entries(of: menu))")
      }
    }
    for role in [Role.a, .base, .b] {
      let menu = controller.headerMenu(for: role).map(Self.entries(of:)) ?? "no menu"
      lines.append("Header \(role.letter): \(menu)")
    }
    try Rendering.write(text: lines.joined(separator: "\n"), named: "context-menus")
  }

  /// The entries of `menu` in one line: separators as a bar, disabled entries in parentheses.
  private static func entries(of menu: NSMenu) -> String {
    menu.items.map { item in
      item.isSeparatorItem ? "|" : item.isEnabled ? item.title : "(\(item.title))"
    }.joined(separator: " · ").replacingOccurrences(of: " · | · ", with: " | ")
  }

  @Test func smallestWindowIsPictured() async throws {
    let session = try await SampleMerges.helloWorld()
    try Windows.picture(
      session, context: SampleMerges.helloWorldContext, look: .light, size: nil,
      named: "helloworld-smallest-light")
  }

  @Test func noticeThatGitNoLongerWaitsIsPictured() async throws {
    let (session, context) = try await Scenario.merges[0].load()
    try Windows.picture(session, context: context, look: .light, named: "notice-light") {
      controller in
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
    try Windows.picture(
      session, context: SessionContext(), look: setting.look,
      options: DisplayOptions(differentiatesWithoutColor: setting.withoutColor),
      size: CGSize(width: 1280, height: 600), named: name)
    try Windows.picture(
      session, context: SessionContext(), look: setting.look,
      options: DisplayOptions(differentiatesWithoutColor: setting.withoutColor),
      size: CGSize(width: 1280, height: 600), named: "\(name)-second-current"
    ) { controller in
      for pane in controller.presentation.allPanes {
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
}

/// A session window that acts as the key window without being shown.
final class KeySessionWindow: SessionWindow {
  override var isKeyWindow: Bool { true }
}

/// Stands in for the responder that saves and closes, which does nothing here.
final class SaveAndCloseStandIn: NSResponder {
  @objc func saveAndClose(_ sender: Any?) {}
}
