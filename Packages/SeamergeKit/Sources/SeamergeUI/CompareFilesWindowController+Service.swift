import AppKit

extension CompareFilesWindowController {
  /// The sentence below the fields after the window was handed a selection it does not compare.
  static var unsupportedSelectionMessage: String {
    String(
      localized: "Seamerge compares two or three files, or two folders.", bundle: .module,
      comment:
        "Compare Files: below the fields after Compare with Seamerge in the Finder was used on a selection that Seamerge does not compare."
    )
  }

  /// Empties the fields, puts `entry`, a file or a folder, in Left and shows the window with the
  /// focus on Right, for the user to choose what to compare it with.
  public func compare(with entry: URL) {
    show(replacingFilesWith: [entry])
    window?.makeFirstResponder(fields[.right])
  }

  /// Empties the fields, puts `urls` in them as ``fill(with:)`` does and shows the window; if
  /// the window takes none of them, it says what Seamerge compares instead.
  public func show(replacingFilesWith urls: [URL]) {
    selection = FileSelection()
    guard fill(with: urls) else {
      showUnsupportedSelection()
      return
    }
    showWindow(nil)
  }

  /// Empties the fields and shows the window with the sentence that says what Seamerge
  /// compares, until the fields change.
  public func showUnsupportedSelection() {
    selection = FileSelection()
    showsUnsupportedSelection = true
    selectionDidChange()
    showWindow(nil)
    announce(Self.unsupportedSelectionMessage)
  }

  /// Puts the files or folders of `comparison` in the fields and shows the window with why they
  /// could not be opened, as if its button had failed to open them.
  public func showFailure(_ error: any Error, opening comparison: FileComparison) {
    selection = FileSelection()
    fill(comparison)
    showWindow(nil)
    guard let window else { return }
    Task { await panels.showFailure(error, in: window) }
  }
}
