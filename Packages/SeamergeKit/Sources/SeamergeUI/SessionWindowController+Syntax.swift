import AppKit
import SyntaxKit

extension SessionWindowController {
  /// Colors the code of every session window by its syntax, or leaves it in the color of text.
  @objc func toggleSyntaxHighlighting(_ sender: Any?) {
    syntaxHighlighting.isOn.toggle()
  }

  /// The language the code is colored as, or `nil` while syntax highlighting is off.
  var syntaxLanguage: LanguageDescription? {
    syntaxHighlighting.isOn ? detectedLanguage : nil
  }

  /// Colors the code as highlighting is set, in whichever window.
  func observeSyntaxHighlighting() {
    NotificationCenter.default.addObserver(
      self, selector: #selector(syntaxHighlightingDidChange(_:)),
      name: SyntaxHighlighting.didChangeNotification, object: syntaxHighlighting.defaults)
  }

  @objc private func syntaxHighlightingDidChange(_ notification: Notification) {
    showSyntax()
  }

  /// Colors the code as ``syntaxLanguage`` says.
  private func showSyntax() {
    presentation.colorSyntax(as: syntaxLanguage)
  }
}
