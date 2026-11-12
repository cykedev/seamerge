import AppKit

/// Learns about clicks on the rows of a pane, from its text and its gutter alike, and about what
/// the text needs from the pane around it.
@MainActor
protocol RowInteraction: AnyObject {
  /// Whether `menu(forRow:)` replaces the standard context menu.
  var suppliesMenus: Bool { get }

  /// Tells that the user clicked `row`, after the click has been handled.
  func rowWasClicked(_ row: Int)

  /// The context menu for a secondary click on `row`, or `nil` for no menu.
  func menu(forRow row: Int) -> NSMenu?

  /// Tells that the selection of the text changed, or the focus that decides how it shows.
  func selectionDidChange()

  /// Asks to expand the collapsed run at `index`, because the user wants to see its rows, a find
  /// result lies in it, or an edit would change rows it hides.
  func askToExpandRun(at index: Int)

  /// The edits that carry out `edit` of the user, which the editing delegate decides; none while
  /// there is no delegate.
  func edits(for edit: PaneEdit) -> [PaneEdit]

  /// Tells that the text carried out `edits`, the answer to an edit of the user, which replaced
  /// `replacedTexts`.
  func didCarryOut(_ edits: [PaneEdit], replacing replacedTexts: [String])

  /// Tells that the text changed by `edit` without having been announced, while it processes the
  /// change.
  func textDidChangeWithoutAnnouncing(_ edit: PaneEdit)

  /// Tells that the text changed and with it the rows, so that what stands beside them follows.
  func textDidChange()
}
