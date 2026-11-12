import MergeModel

extension SessionCommand {
  /// A menu of the main menu that holds commands of a session window.
  public enum Menu: CaseIterable, Sendable {
    /// The File menu.
    case file

    /// The Edit menu.
    case edit

    /// The View menu.
    case view

    /// The Go menu.
    case go

    /// The Compare menu.
    case compare
  }

  /// The commands of a session window in `menu`, in order, each group between separators.
  ///
  /// The menus hold more than these, such as Save and Copy; the commands stand where the
  /// concept of the menus puts them among those.
  public static func groups(in menu: Menu) -> [[SessionCommand]] {
    switch menu {
    case .file: [[.openInEditor], [.skipRemainingFiles]]
    case .edit: [[.copyBlock]]
    case .view:
      [
        [.toggleBase, .toggleResultMaximized],
        [
          .toggleScrollSynchronization, .toggleInvisibles, .showAllLines, .collapseUnchangedLines,
        ],
        [.zoomIn, .zoomOut, .actualSize],
      ]
    case .go:
      [
        [.nextConflict, .previousConflict],
        [.nextChange, .previousChange, .firstChange, .lastChange],
        [.nextPane, .previousPane], [.goToLine],
      ]
    case .compare:
      [
        [.compareExactly, .ignoreLineEndings, .ignoreWhitespaceChanges, .ignoreAllWhitespace],
        [.swapSides],
      ]
    }
  }

  /// The groups of the options menu of the toolbar of a window of `kind`: those of the Compare
  /// and View menus, without the commands that never act in such a window.
  ///
  /// The main menu shows those deactivated; the options menu belongs to one window and leaves
  /// them out.
  static func optionsGroups(in kind: Session.Kind) -> [[SessionCommand]] {
    (groups(in: .compare) + groups(in: .view)).map { $0.filter { $0.acts(in: kind) } }
      .filter { !$0.isEmpty }
  }

  /// Whether the command can act in a window of `kind` at all: Swap Sides and Skip Remaining
  /// Files only in a comparison, the commands of the base and the result only in a merge.
  private func acts(in kind: Session.Kind) -> Bool {
    switch self {
    case .swapSides, .skipRemainingFiles: kind == .diff
    case .nextConflict, .previousConflict, .toggleBase, .toggleResultMaximized: kind == .merge
    default: true
    }
  }

  /// The jumps that the context menu offers, on a changed block or on unchanged text, as far as
  /// each has an effect there.
  static func contextMenuJumps(onChangedBlock: Bool) -> [SessionCommand] {
    onChangedBlock ? [.nextConflict, .nextChange] : [.nextConflict]
  }
}
