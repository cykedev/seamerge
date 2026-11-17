import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Highlight Syntax and the choice of the language: in the View menu and the footer, for every
/// pane of the window, kept for the path of the file while the app runs, and Plain Text, which
/// colors nothing.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct SyntaxChoiceTests {
  @Test func highlightSyntaxTurnsOffTheColorsOfItsWindowAndBackOn() async throws {
    let settings = UserSettings.private()
    let session = try await SyntaxFixture.merge()
    let first = try Windows.controller(for: session, settings: settings)
    let second = try Windows.controller(for: session, settings: settings)
    await SyntaxFixture.lexing(of: first)
    let item = Self.item(.toggleSyntaxHighlighting)
    #expect(first.validateUserInterfaceItem(item) && item.state == .on)

    first.toggleSyntaxHighlighting(nil)

    #expect(Windows.panes(of: first).allSatisfy { $0.syntaxProvider == nil })
    #expect(first.presentation.syntax.language == nil)
    #expect(first.validateUserInterfaceItem(item) && item.state == .off)
    #expect(second.presentation.syntax.language?.name == "Swift")
    #expect(second.validateUserInterfaceItem(item) && item.state == .on)
    #expect(settings.highlightsSyntax)

    first.toggleSyntaxHighlighting(nil)
    await SyntaxFixture.lexing(of: first)
    #expect(first.presentation.syntax.language?.name == "Swift")
  }

  @Test func newWindowColorsItsCodeAsTheSettingsSay() async throws {
    let settings = UserSettings.private()
    let session = try await SyntaxFixture.merge()

    settings.highlightsSyntax = false

    let controller = try Windows.controller(for: session, settings: settings)
    #expect(controller.presentation.syntax.language == nil)
    let item = Self.item(.toggleSyntaxHighlighting)
    #expect(controller.validateUserInterfaceItem(item) && item.state == .off)
  }

  @Test func chosenLanguageColorsEveryPaneAndStaysForThePathOfTheFile() async throws {
    let choices = SyntaxChoices()
    let session = try await SyntaxFixture.merge()
    let controller = try Windows.controller(for: session, syntaxChoices: choices)
    await SyntaxFixture.lexing(of: controller)

    controller.chooseSyntax(try Self.item(choosing: "Python"))

    #expect(controller.presentation.syntax.language?.name == "Python")
    await SyntaxFixture.lexing(of: controller)
    // In Python, `let` is no keyword.
    let base = try #require(controller.layout.sourcePane(.base)?.syntaxProvider)
    #expect(base.tokens(inLine: 1).allSatisfy { $0.kind != .keyword })
    let again = try Windows.controller(for: session, syntaxChoices: choices)
    #expect(again.presentation.syntax.language?.name == "Python")
    let otherFile = try Windows.controller(
      for: try await SyntaxFixture.merge(named: "Other.swift"), syntaxChoices: choices)
    #expect(otherFile.presentation.syntax.language?.name == "Swift")
    let otherLaunch = try Windows.controller(for: session, syntaxChoices: SyntaxChoices())
    #expect(otherLaunch.presentation.syntax.language?.name == "Swift")
  }

  @Test func codeLosesItsColorsAtOnceWhenHighlightingIsTurnedOffOrPlainTextChosen() async throws {
    for turnsOff in [true, false] {
      let controller = try Windows.controller(for: try await SyntaxFixture.merge())
      await SyntaxFixture.lexing(of: controller)
      let base = try #require(controller.layout.sourcePane(.base))
      #expect(try Self.color(at: 1, in: base) != nil, "turns off \(turnsOff)")

      if turnsOff {
        controller.toggleSyntaxHighlighting(nil)
      } else {
        controller.chooseSyntax(try Self.item(choosing: "Plain Text"))
      }

      #expect(try Self.color(at: 1, in: base) == nil, "turns off \(turnsOff)")
      if !turnsOff {
        await SyntaxFixture.lexing(of: controller)
        #expect(try Self.color(at: 1, in: base) == nil, "lexed as plain text")
      }
    }
  }

  @Test func plainTextColorsNothing() async throws {
    let controller = try Windows.controller(
      for: try await SyntaxFixture.merge())
    controller.chooseSyntax(try Self.item(choosing: "Plain Text"))
    await SyntaxFixture.lexing(of: controller)

    for pane in Windows.panes(of: controller) {
      let provider = try #require(pane.syntaxProvider)
      for line in 0..<pane.content.lineNumbers.count {
        #expect(provider.tokens(inLine: line).isEmpty)
      }
    }
  }

  @Test func menuAndFooterShowTheRecognizedAndTheChosenLanguage() async throws {
    let controller = try Windows.controller(
      for: try await SyntaxFixture.merge())
    let automatic = SyntaxChoice.automatic.menuItem()
    let python = try Self.item(choosing: "Python")
    let button = controller.content.footer.syntaxChoiceButton
    #expect(controller.validateUserInterfaceItem(automatic))
    #expect(automatic.title == "Automatic (Swift)" && automatic.state == .on)
    #expect(button.title == "Swift")
    #expect(button.itemArray.first?.title == "Automatic (Swift)")
    #expect(button.accessibilityLabel() == "Syntax")

    controller.chooseSyntax(python)

    #expect(controller.validateUserInterfaceItem(automatic) && automatic.state == .off)
    #expect(controller.validateUserInterfaceItem(python) && python.state == .on)
    #expect(button.title == "Python")
    #expect(button.itemArray.first { $0.state == .on }?.title == "Python")
  }

  @Test func languageCannotBeChosenWhileHighlightingIsOff() async throws {
    let controller = try Windows.controller(
      for: try await SyntaxFixture.merge())
    controller.toggleSyntaxHighlighting(nil)

    #expect(!controller.validateUserInterfaceItem(try Self.item(choosing: "Python")))
    #expect(!controller.content.footer.syntaxChoiceButton.isEnabled)
    controller.chooseSyntax(try Self.item(choosing: "Python"))
    #expect(controller.syntaxChoice == .automatic)
  }

  @Test func togglesOfTheFooterStayInPlaceWhateverTheLanguage() async throws {
    let controller = try Windows.controller(
      for: try await SyntaxFixture.merge())
    let footer = controller.content.footer
    let toggle = try #require(footer.button(of: .invisibles))
    footer.layoutSubtreeIfNeeded()
    let place = toggle.frame.minX
    for language in ["C", "Objective-C", "Plain Text"] {
      controller.chooseSyntax(try Self.item(choosing: language))
      footer.layoutSubtreeIfNeeded()
      #expect(toggle.frame.minX == place, "\(language)")
    }
  }

  /// The color that the text at `offset` of `pane` is drawn in, or `nil` for the color of text.
  private static func color(at offset: Int, in pane: PaneView) throws -> NSColor? {
    let manager = try #require(pane.documentView.textLayoutManager)
    let start = manager.documentRange.location
    let location = try #require(manager.location(start, offsetBy: offset))
    let fragment = try #require(manager.textLayoutFragment(for: location))
    let paragraph = try #require(fragment.textElement as? NSTextParagraph)
    let paragraphStart = manager.offset(
      from: start, to: try #require(paragraph.elementRange).location)
    let color =
      paragraph.attributedString.attribute(
        .foregroundColor, at: offset - paragraphStart, effectiveRange: nil) as? NSColor
    return color == NSColor.textColor ? nil : color
  }

  /// A menu item of the main menu that sends `command`.
  private static func item(_ command: SessionCommand) -> NSMenuItem {
    NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
  }

  /// The menu item of the Syntax menu titled `title`.
  private static func item(choosing title: String) throws -> NSMenuItem {
    try #require(SyntaxChoice.groups.joined().first { $0.title() == title }?.menuItem())
  }
}
