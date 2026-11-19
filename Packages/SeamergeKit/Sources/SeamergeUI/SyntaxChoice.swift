public import AppKit
import SyntaxKit

/// A choice of the language that the code of a window is colored as: the one the window
/// recognized, one language, or none.
///
/// The submenu Syntax of the View menu and the pop-up button of the footer offer the same
/// choices; the menu items send ``action`` with the choice as their represented object, and the
/// window carries it out and puts a checkmark at the one in effect.
public struct SyntaxChoice: Hashable, Sendable {
  /// The language chosen, or `nil` for the one the window recognizes.
  let chosenLanguage: LanguageDescription?

  /// The language the window recognizes by the name and first line of its file.
  static let automatic = SyntaxChoice(chosenLanguage: nil)

  /// Colors the code as `language`.
  static func language(_ language: LanguageDescription) -> SyntaxChoice {
    SyntaxChoice(chosenLanguage: language)
  }

  /// The choices in the order of their menu, each group between separators: Automatic, the
  /// languages by name, and Plain Text, which colors nothing.
  public static let groups: [[SyntaxChoice]] = [
    [.automatic],
    LanguageDescription.all.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }.map(SyntaxChoice.language),
    [.language(.plainText)],
  ]

  /// The language the code is colored as with this choice, where the window recognized
  /// `detected`.
  func language(detected: LanguageDescription) -> LanguageDescription {
    chosenLanguage ?? detected
  }

  /// The name of the choice in a menu; for Automatic, with the language the window recognized,
  /// if it is known.
  func title(detected: LanguageDescription? = nil) -> String {
    guard chosenLanguage == nil else { return languageTitle(of: chosenLanguage ?? .plainText) }
    guard let detected else {
      return String(
        localized: "Automatic", bundle: .module,
        comment: "Syntax menu: color the code as the language recognized from the file.")
    }
    return String(
      localized: "Automatic (\(languageTitle(of: detected)))", bundle: .module,
      comment:
        "Syntax menu: color the code as the language recognized from the file, which is named in parentheses, such as Automatic (Swift)."
    )
  }

  /// The name of `language` as the menu shows it.
  func languageTitle(of language: LanguageDescription) -> String {
    language == .plainText
      ? String(
        localized: "Plain Text", bundle: .module,
        comment: "Syntax menu: color nothing; also the name of a file of no known language.")
      : language.name
  }

  /// The title of the submenu of the choices.
  public static var menuTitle: String {
    String(
      localized: "Syntax", bundle: .module,
      comment: "View menu: the submenu of the languages the code can be colored as.")
  }

  /// The help tag of the choice in the footer while the code is colored.
  static var help: String {
    String(
      localized: "Choose the language the code is colored as", bundle: .module,
      comment: "Help tag of the syntax pop-up button in the footer.")
  }

  /// The help tag of the choice in the footer while syntax highlighting is off.
  static var disabledHelp: String {
    String(
      localized: "Turn on Highlight Syntax in the View menu to color the code", bundle: .module,
      comment: "Help tag of the syntax pop-up button in the footer while highlighting is off.")
  }

  /// The action the menu items send along the responder chain.
  public static let action = #selector(SessionWindowController.chooseSyntax(_:))

  /// A menu item that sends the choice.
  public func menuItem() -> NSMenuItem {
    let item = NSMenuItem(title: title(), action: Self.action, keyEquivalent: "")
    item.representedObject = self
    return item
  }

  /// The choice that `item` sends, if it sends one.
  init?(item: Any?) {
    guard let choice = (item as? NSMenuItem)?.representedObject as? SyntaxChoice else {
      return nil
    }
    self = choice
  }

  private init(chosenLanguage: LanguageDescription?) {
    self.chosenLanguage = chosenLanguage
  }
}
