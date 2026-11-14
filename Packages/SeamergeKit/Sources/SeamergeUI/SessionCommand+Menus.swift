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

    /// The Merge menu.
    case merge
  }

  /// The commands of a session window in `menu`, in order, each group between separators.
  ///
  /// The menus hold more than these, such as Save and Copy; the commands stand where the
  /// concept of the menus puts them among those.
  public static func groups(in menu: Menu) -> [[SessionCommand]] {
    switch menu {
    case .file:
      [
        [.changeFiles], [.openInEditor], [.save, .saveAs, .saveAndClose],
        [.leaveUnresolved, .skipRemainingFiles],
      ]
    case .edit: [[.copyBlock]]
    case .view:
      [
        [.toggleBase, .toggleResultMaximized],
        [
          .toggleScrollSynchronization, .toggleLineAlignment, .toggleSyntaxHighlighting,
          .toggleInvisibles, .toggleLineWrapping, .showAllLines, .collapseUnchangedLines,
        ],
        [.zoomIn, .zoomOut, .actualSize],
        [.toggleFooter],
      ]
    case .go:
      [
        [.nextConflict, .previousConflict],
        [.nextChange, .previousChange, .firstChange, .lastChange],
        [.nextFile, .previousFile], [.nextPane, .previousPane], [.goToLine],
      ]
    case .compare:
      [
        [.compareExactly, .ignoreLineEndings, .ignoreWhitespaceChanges, .ignoreAllWhitespace],
        [.swapSides],
      ]
    case .merge:
      [
        [
          .useA, .useBase, .useB, .useAThenB, .useBThenA, .useNone, .toggleSourceA,
          .toggleSourceBase, .toggleSourceB, .resolveManually,
        ],
        [.resetChange, .reopenAllConflicts, .resetAllDecisions],
        [.resolveAllWithA, .resolveAllWithB],
      ]
    }
  }

  /// The name of the choice of the comparison mode, where the toolbar or the footer offers the
  /// commands of the Compare menu that choose it.
  static var comparisonModeLabel: String {
    String(
      localized: "Comparison", bundle: .module,
      comment:
        "The choice of the comparison mode: a toolbar item and the pop-up button of the footer.")
  }

  /// The help tag of the choice of the comparison mode.
  static var comparisonModeHelp: String {
    String(
      localized: "Choose how lines are compared", bundle: .module,
      comment: "Help tag of the choice of the comparison mode in the toolbar and the footer.")
  }

  /// The jumps that the context menu offers, on a changed block or on unchanged text, as far as
  /// each has an effect there.
  static func contextMenuJumps(onChangedBlock: Bool) -> [SessionCommand] {
    onChangedBlock ? [.nextConflict, .nextChange] : [.nextConflict]
  }
}
