import AppKit
import FolderCompare
import PaneKit

extension CollectedFile.Change {
  /// How the list shows what happened to a file: a sign, its color, and a word for VoiceOver and
  /// the help tag.
  struct Presentation {
    /// The name of the symbol of the sign, or `nil` for a file that only changed, which most files
    /// of a list are; the signs stand out for the others.
    let symbolName: String?

    /// The word for what happened.
    let word: String

    private let colorRole: ColorRole?

    /// The color of the sign: that of the side that has the file alone, the color of the earlier
    /// side for a deleted file and of the later side for a new one, as in the panes; a quiet
    /// gray for the others.
    func color(in theme: Theme) -> NSColor {
      colorRole.map(theme.symbolColor(for:)) ?? .secondaryLabelColor
    }

    /// Why a side cannot be read, for a file whose sides cannot be compared.
    let reason: String?

    /// The help tag of a row: the whole path and what happened, and why where a side cannot be
    /// read.
    func toolTip(for path: String) -> String {
      guard let reason else {
        return String(
          localized: "\(path) (\(word))", bundle: .module,
          comment:
            "Help tag of a file in the sidebar: its path and what happened, such as Sources/App.swift (Modified)."
        )
      }
      return String(
        localized: "\(path) (\(word): \(reason))", bundle: .module,
        comment:
          "Help tag of a file in the sidebar that cannot be read: its path, the state and the reason, such as Logs (Can’t Read: You don’t have permission.)."
      )
    }

    fileprivate init(
      symbolName: String?, word: String, colorRole: ColorRole?, reason: String? = nil
    ) {
      self.symbolName = symbolName
      self.word = word
      self.colorRole = colorRole
      self.reason = reason
    }
  }

  /// How the list shows the change.
  var presentation: Presentation {
    switch self {
    case .modified:
      Presentation(
        symbolName: nil,
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
    case .identical:
      Presentation(
        symbolName: "equal.circle",
        word: String(
          localized: "Identical", bundle: .module,
          comment: "A file in the sidebar whose two sides hold the same bytes."),
        colorRole: nil)
    case .unreadable(let reason):
      Presentation(
        symbolName: "exclamationmark.circle",
        word: String(
          localized: "Can’t Read", bundle: .module,
          comment: "A file or folder in the sidebar of which a side cannot be read."),
        colorRole: nil, reason: reason)
    }
  }
}
