import AppKit
import PaneKit

extension CollectedFile.Change {
  /// How the list shows what happened to a file: a sign, its color, and a word for VoiceOver and
  /// the help tag.
  struct Presentation {
    /// The name of the symbol of the sign.
    let symbolName: String

    /// The word for what happened.
    let word: String

    private let colorRole: ColorRole?

    /// The color of the sign: that of the side that has the file alone, the color of the earlier
    /// side for a deleted file and of the later side for a new one, as in the panes; a quiet
    /// gray for a file that changed.
    func color(in theme: Theme) -> NSColor {
      colorRole.map(theme.symbolColor(for:)) ?? .secondaryLabelColor
    }

    /// The help tag of a row: the whole path and what happened.
    func toolTip(for path: String) -> String {
      String(
        localized: "\(path) (\(word))", bundle: .module,
        comment:
          "Help tag of a file in the sidebar: its path and what happened, such as Sources/App.swift (Modified)."
      )
    }

    fileprivate init(symbolName: String, word: String, colorRole: ColorRole?) {
      self.symbolName = symbolName
      self.word = word
      self.colorRole = colorRole
    }
  }

  /// How the list shows the change.
  var presentation: Presentation {
    switch self {
    case .modified:
      Presentation(
        symbolName: "circle.fill",
        word: String(
          localized: "Modified", bundle: .module,
          comment: "A file in the sidebar whose two sides differ."),
        colorRole: nil)
    case .added:
      Presentation(
        symbolName: "plus.circle",
        word: String(
          localized: "New", bundle: .module,
          comment: "A file in the sidebar that has no earlier side."),
        colorRole: .b)
    case .deleted:
      Presentation(
        symbolName: "minus.circle",
        word: String(
          localized: "Deleted", bundle: .module,
          comment: "A file in the sidebar that has no later side."),
        colorRole: .a)
    }
  }
}
