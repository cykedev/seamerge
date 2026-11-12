import AppKit

/// What a window asks or tells the user while it switches to another comparison.
///
/// A window shows both as sheets; the window takes the prompts when it is made.
@MainActor
protocol ComparisonPrompts: AnyObject {
  /// Asks whether to switch although `count` decisions would be lost, and tells whether to.
  func confirmDiscarding(_ count: Int, in window: NSWindow) async -> Bool

  /// Tells that the files could not be compared anew.
  func reportFailedComparison(in window: NSWindow) async
}

/// The prompts of a window as sheets.
@MainActor
final class ComparisonSheets: ComparisonPrompts {
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
