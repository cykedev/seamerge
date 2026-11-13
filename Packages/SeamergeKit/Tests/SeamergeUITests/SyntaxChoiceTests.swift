import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Highlight Syntax: in the View menu, for every pane of every window, kept across launches.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct SyntaxChoiceTests {
  @Test func highlightSyntaxTurnsOffTheColorsOfEveryWindowAndBackOn() async throws {
    let defaults = UserDefaults.privateSuite()
    let session = try await SyntaxFixture.merge()
    let first = try Windows.controller(for: session, defaults: defaults)
    let second = try Windows.controller(for: session, defaults: defaults)
    await SyntaxFixture.lexing(of: first)
    let item = Self.item(.toggleSyntaxHighlighting)
    #expect(first.validateUserInterfaceItem(item) && item.state == .on)

    first.toggleSyntaxHighlighting(nil)

    for controller in [first, second] {
      #expect(Windows.panes(of: controller).allSatisfy { $0.syntaxProvider == nil })
      #expect(controller.presentation.syntax.language == nil)
    }
    #expect(second.validateUserInterfaceItem(item) && item.state == .off)
    #expect(!SyntaxHighlighting(defaults: defaults).isOn)
    let third = try Windows.controller(for: session, defaults: defaults)
    #expect(third.presentation.syntax.language == nil)

    second.toggleSyntaxHighlighting(nil)
    await SyntaxFixture.lexing(of: first)
    #expect(first.presentation.syntax.language?.name == "Swift")
  }

  /// A menu item of the main menu that sends `command`.
  private static func item(_ command: SessionCommand) -> NSMenuItem {
    NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
  }
}
