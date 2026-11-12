import AppKit

/// The panels and sheets of the window Compare Files: the open panel of a field, and the sheet
/// that says why files could not be opened.
@MainActor
protocol CompareFilesPanels {
  /// Lets the user choose a file for the field `role` of `window`, and returns it, or `nil` if
  /// the user cancelled.
  func chooseFile(for role: String, in window: NSWindow) async -> URL?

  /// Shows on `window` why its files could not be opened, until the user dismisses it.
  func showFailure(_ error: any Error, in window: NSWindow) async
}

/// The panels of the system, as sheets on the window.
struct SystemPanels: CompareFilesPanels {
  func chooseFile(for role: String, in window: NSWindow) async -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.message = String(
      localized: "Choose the file for \(role).", bundle: .module,
      comment: "Open panel of a field of Compare Files, such as Choose the file for Left.")
    panel.prompt = String(
      localized: "Choose", bundle: .module, comment: "The button of the open panel of a field.")
    guard await panel.beginSheetModal(for: window) == .OK else { return nil }
    return panel.url
  }

  func showFailure(_ error: any Error, in window: NSWindow) async {
    _ = await NSAlert(error: error).beginSheetModal(for: window)
  }
}
