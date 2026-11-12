import AppKit

/// Learns about clicks on the rows of a pane, from its text and its gutter alike.
@MainActor
protocol RowInteraction: AnyObject {
  /// Whether `menu(forRow:)` replaces the standard context menu.
  var suppliesMenus: Bool { get }

  /// Tells that the user clicked `row`, after the click has been handled.
  func rowWasClicked(_ row: Int)

  /// The context menu for a secondary click on `row`, or `nil` for no menu.
  func menu(forRow row: Int) -> NSMenu?
}
