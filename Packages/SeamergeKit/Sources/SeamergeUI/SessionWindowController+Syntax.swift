import AppKit
import SyntaxKit

extension SessionWindowController {
  /// Colors the code of the window by its syntax, or leaves it in the color of text.
  @objc func toggleSyntaxHighlighting(_ sender: Any?) {
    highlightsSyntax.toggle()
    showSyntax()
  }

  /// Colors the code of the window as the language of the choice that `sender` sends, and keeps
  /// the choice for the file while the app runs.
  @objc func chooseSyntax(_ sender: Any?) {
    guard let choice = SyntaxChoice(item: sender), canChooseSyntax else { return }
    syntaxChoices[syntaxPath] = choice
    showSyntax()
  }

  /// The choice of the language in effect for the file of the window.
  var syntaxChoice: SyntaxChoice {
    syntaxChoices[syntaxPath]
  }

  /// The language the code is colored as, or `nil` while syntax highlighting is off.
  var syntaxLanguage: LanguageDescription? {
    highlightsSyntax ? syntaxChoice.language(detected: detectedLanguage) : nil
  }

  /// Whether a language can be chosen now: while the code is colored and the window shows the
  /// lines of its files.
  var canChooseSyntax: Bool {
    highlightsSyntax && unavailable == nil && binaryMerge == nil
  }

  /// Puts a checkmark at the choice in effect, names the recognized language in Automatic, and
  /// tells whether `item` can be chosen now.
  func validate(_ choice: SyntaxChoice, item: NSMenuItem) -> Bool {
    item.title = choice.title(detected: detectedLanguage)
    item.state = choice == syntaxChoice ? .on : .off
    return canChooseSyntax
  }

  /// Colors the code as ``syntaxLanguage`` says and shows the choice in the footer.
  private func showSyntax() {
    presentation.colorSyntax(as: syntaxLanguage)
    updateFooter()
  }
}
