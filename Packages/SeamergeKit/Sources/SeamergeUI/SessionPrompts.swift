import AppKit

/// What a window asks or tells the user before it discards work, and when it cannot switch to
/// another comparison.
///
/// A window shows them as sheets; the window takes the prompts when it is made.
@MainActor
protocol SessionPrompts: AnyObject {
  /// Asks whether to switch although `count` decisions would be lost, and tells whether to.
  func confirmDiscarding(_ count: Int, in window: NSWindow) async -> Bool

  /// Asks whether to reset every decision although it discards the text typed by hand in
  /// `count` blocks, and tells whether to.
  func confirmResettingAll(discardingHandwritingIn count: Int, in window: NSWindow) async -> Bool

  /// Tells that the files could not be compared anew.
  func reportFailedComparison(in window: NSWindow) async
}

/// The prompts of a window as sheets.
@MainActor
final class SessionSheets: SessionPrompts {
  func confirmDiscarding(_ count: Int, in window: NSWindow) async -> Bool {
    let alert = NSAlert()
    alert.messageText = String(
      localized: "The switch discards \(count) decisions.", bundle: .module,
      comment: "Sheet before switching the comparison, such as The switch discards 3 decisions.")
    // The first button is the default one, which keeps the decisions.
    alert.addButton(
      withTitle: String(
        localized: "Cancel", bundle: .module, comment: "Button: close the sheet and do nothing."))
    alert.addButton(
      withTitle: String(localized: "Switch", bundle: .module, comment: "Button: switch anyway."))
    return await alert.beginSheetModal(for: window) == .alertSecondButtonReturn
  }

  func confirmResettingAll(discardingHandwritingIn count: Int, in window: NSWindow) async -> Bool {
    let alert = NSAlert()
    alert.messageText = String(
      localized: "This discards handwritten text in \(count) blocks.", bundle: .module,
      comment: "Sheet before resetting every decision, such as in 3 blocks.")
    // The first button is the default one, which keeps the text.
    alert.addButton(
      withTitle: String(
        localized: "Cancel", bundle: .module, comment: "Button: close the sheet and do nothing."))
    alert.addButton(
      withTitle: String(
        localized: "Reset", bundle: .module,
        comment:
          "Resetting decisions: the button of the sheet before resetting every one, and the submenu of a context menu with the ways to reset."
      ))
    return await alert.beginSheetModal(for: window) == .alertSecondButtonReturn
  }

  func reportFailedComparison(in window: NSWindow) async {
    let alert = NSAlert()
    alert.messageText = String(
      localized: "Couldn’t Compare the Files Anew", bundle: .module,
      comment: "Sheet after switching the comparison failed.")
    alert.informativeText = String(
      localized: "The window still shows the previous comparison.", bundle: .module,
      comment: "Sheet after switching the comparison failed: what happens next.")
    _ = await alert.beginSheetModal(for: window)
  }
}
