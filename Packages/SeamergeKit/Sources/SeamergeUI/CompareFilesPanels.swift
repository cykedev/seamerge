import AppKit

/// What the open panel of a field of a sheet of files lets the user choose.
enum FileChoice: Equatable {
  /// A file only, as for the base.
  case file

  /// A file or a folder, as for an outer field.
  case fileOrFolder

  /// A folder only, as for File > Compare Folders….
  case folder
}

/// The panels and sheets of a sheet of files: the open panel of a field, and the sheet that says
/// why files could not be opened.
@MainActor
protocol CompareFilesPanels {
  /// Lets the user choose what `choice` allows for the field `role` of `window`, and returns it,
  /// a folder as a directory path, or `nil` if the user cancelled.
  func chooseFile(_ choice: FileChoice, for role: String, in window: NSWindow) async -> URL?

  /// Shows on `window` why its files could not be opened, until the user dismisses it.
  func showFailure(_ error: any Error, in window: NSWindow) async
}

/// The panels of the system, as sheets on the window.
struct SystemPanels: CompareFilesPanels {
  func chooseFile(_ choice: FileChoice, for role: String, in window: NSWindow) async -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = choice != .folder
    panel.canChooseDirectories = choice != .file
    panel.treatsFilePackagesAsDirectories = false
    panel.allowsMultipleSelection = false
    panel.message =
      switch choice {
      case .file:
        String(
          localized: "Choose the file for \(role).", bundle: .module,
          comment: "Open panel of a field of Compare Files, such as Choose the file for Left.")
      case .fileOrFolder:
        String(
          localized: "Choose the file or folder for \(role).", bundle: .module,
          comment:
            "Open panel of an outer field of Compare Files, such as Choose the file or folder for Left."
        )
      case .folder:
        String(
          localized: "Choose the folder for \(role).", bundle: .module,
          comment:
            "Open panel of Compare Folders, such as Choose the folder for Left Folder.")
      }
    panel.prompt = String(
      localized: "Choose", bundle: .module, comment: "The button of the open panel of a field.")
    guard await panel.beginSheetModal(for: window) == .OK else { return nil }
    return panel.url.flatMap(FileDrop.entry(at:))
  }

  func showFailure(_ error: any Error, in window: NSWindow) async {
    _ = await NSAlert(error: error).beginSheetModal(for: window)
  }
}
