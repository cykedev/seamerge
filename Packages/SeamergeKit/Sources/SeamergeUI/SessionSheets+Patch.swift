import AppKit
import UniformTypeIdentifiers

/// The sheets of exporting and copying a patch.
extension SessionSheets {
  func choosePatchDestination(
    suggesting name: String, fileCount: Int?, in window: NSWindow
  ) async -> URL? {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    panel.canCreateDirectories = true
    // The type of patches takes the extension .diff as well as .patch.
    panel.allowedContentTypes = UTType("public.patch-file").map { [$0] } ?? []
    if let fileCount {
      panel.message = String(
        localized: "\(fileCount) files", bundle: .module,
        comment:
          "Message of the choice of the place of a patch: the files it holds, such as 12 files.")
    }
    guard await panel.beginSheetModal(for: window) == .OK else { return nil }
    return panel.url
  }

  func reportFailedPatch(_ error: PatchError, exporting name: String?, in window: NSWindow) async {
    let alert = NSAlert()
    alert.messageText =
      if let name {
        String(
          localized: "Couldn’t Export “\(name)”", bundle: .module,
          comment: "Sheet after exporting a patch to a file failed.")
      } else {
        String(
          localized: "Couldn’t Copy the Patch", bundle: .module,
          comment: "Sheet after copying a patch failed.")
      }
    alert.informativeText = [error.errorDescription, error.recoverySuggestion].compactMap(\.self)
      .joined(separator: " ")
    _ = await Self.present(alert, in: window)
  }
}
