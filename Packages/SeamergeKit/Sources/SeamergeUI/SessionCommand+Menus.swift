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
    case .file: []
    case .edit: [[.copyBlock]]
    case .view:
      []
    case .go:
      [
        [.nextConflict, .previousConflict],
        [.nextChange, .previousChange, .firstChange, .lastChange],
      ]
    case .compare:
      []
    }
  }

  /// The jumps that the context menu offers, on a changed block or on unchanged text, as far as
  /// each has an effect there.
  static func contextMenuJumps(onChangedBlock: Bool) -> [SessionCommand] {
    onChangedBlock ? [.nextConflict, .nextChange] : [.nextConflict]
  }
}
