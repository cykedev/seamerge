public import AppKit
import MergeModel

/// The sheets Compare Files and Merge Files on the welcome window, and what the window does with
/// files from the Dock, the service Compare with Seamerge and a drop.
extension WelcomeWindowController {
  /// Shows the window and on it the sheet Compare Files.
  @objc public func showCompareFiles(_ sender: Any?) {
    showFilesSheet(.compare)
  }

  /// Shows the window and on it the sheet Merge Files.
  @objc public func showMergeFiles(_ sender: Any?) {
    showFilesSheet(.merge)
  }

  /// Shows the window and on it the sheet Compare Files with the open panel for the left folder.
  ///
  /// What the sheet already holds stays until the user chooses the folder, which takes the place
  /// of the left field only.
  @objc public func showCompareFolders(_ sender: Any?) {
    showFilesSheet(.compare) { sheet in sheet.choose(.folder, for: .left) }
  }

  /// Puts `urls` in the fields of a sheet, as if they were dropped on it, and shows the window
  /// with it: up to two files or folders in Compare Files, three files in Merge Files; tells
  /// whether the window takes them.
  @discardableResult
  public func fill(with urls: [URL]) -> Bool {
    let entries = Self.entries(urls)
    guard let purpose = Self.purpose(for: entries) else { return false }
    showFilesSheet(purpose) { sheet in sheet.fill(with: entries) }
    return true
  }

  /// Shows the window with the sheet Compare Files and `entry`, a file or a folder, in Left in
  /// place of what was there, with the focus on Right, for the user to choose what to compare it
  /// with.
  public func compare(with entry: URL) {
    showFilesSheet(.compare) { sheet in
      sheet.selection = FileSelection(kind: .diff)
      sheet.fill(with: [entry])
      sheet.window?.makeFirstResponder(sheet.fields[.right])
    }
  }

  /// Shows the window with `urls` in the fields of a sheet in place of what was there, as
  /// ``fill(with:)`` does; if the window takes none of them, it says what Seamerge compares
  /// instead.
  public func show(replacingFilesWith urls: [URL]) {
    let entries = Self.entries(urls)
    guard let purpose = Self.purpose(for: entries) else {
      showUnsupportedSelection()
      return
    }
    showFilesSheet(purpose) { sheet in
      sheet.selection = FileSelection(kind: purpose.kind)
      sheet.fill(with: entries)
    }
  }

  /// Shows the window with the sheet Compare Files, empty, with the sentence that says what
  /// Seamerge compares, until the fields change.
  public func showUnsupportedSelection() {
    showFilesSheet(.compare) { [announce] sheet in
      sheet.showUnsupportedSelection()
      announce(CompareFilesWindowController.unsupportedSelectionMessage)
    }
  }

  /// Shows the window with the files or folders of `comparison` in the fields of its sheet and
  /// why they could not be opened, as if the button of the sheet had failed to open them.
  public func showFailure(_ error: any Error, opening comparison: FileComparison) {
    showFilesSheet(comparison.kind == .merge ? .merge : .compare) { [panels] sheet in
      sheet.selection = FileSelection(kind: comparison.kind)
      sheet.fill(comparison)
      guard let sheetWindow = sheet.window else { return }
      Task { await panels.showFailure(error, in: sheetWindow) }
    }
  }

  /// Shows the window in front and on it the sheet for `purpose`, then does `prepare` with it.
  ///
  /// A sheet of files for another purpose gives way; while another sheet hangs on the window,
  /// such as Set Up Git Integration, the sheet of files waits until it has ended.
  func showFilesSheet(
    _ purpose: CompareFilesWindowController.Purpose,
    then prepare: @escaping (CompareFilesWindowController) -> Void = { _ in }
  ) {
    guard let window else { return }
    // In front even while it is open behind a session window, so that the command shows its
    // sheet where the user sees it.
    showWindow(nil)
    if let filesSheet, filesSheet.purpose == purpose {
      prepare(filesSheet)
      return
    }
    if let sheetWindow = filesSheet?.window {
      window.endSheet(sheetWindow)
    }
    guard window.attachedSheet == nil else {
      pendingFilesSheet = { [weak self] in self?.showFilesSheet(purpose, then: prepare) }
      return
    }
    let sheet = CompareFilesWindowController(
      purpose: purpose, displayOptions: displayOptions, panels: panels,
      window: CompareFilesWindow(), announce: announce)
    sheet.onOpen = { [weak self] comparison in try await self?.openFromSheet(comparison) }
    guard let sheetWindow = sheet.window else { return }
    filesSheet = sheet
    window.beginSheet(sheetWindow) { [weak self, weak sheet] _ in
      guard let self, filesSheet === sheet else { return }
      filesSheet = nil
    }
    prepare(sheet)
    sheet.focusFirstEmptyField()
  }

  /// Opens `comparison` from the sheet of files; once its window shows, remembers it and closes
  /// the sheet and the window.
  ///
  /// - Throws: Why the files cannot be opened; the sheet shows it and keeps them.
  private func openFromSheet(_ comparison: FileComparison) async throws {
    guard let delegate else { return }
    try await delegate.welcomeWindowController(self, open: comparison)
    didOpen(comparison)
  }

  /// `urls` as the window takes them: a folder as a directory path; whatever cannot be looked at
  /// counts as a file, which opening then reports.
  private static func entries(_ urls: [URL]) -> [URL] {
    urls.map { FileDrop.entry(at: $0) ?? $0 }
  }

  /// The sheet that takes `entries`: Compare Files for one or two files or folders, Merge Files
  /// for three files; `nil` for anything else.
  static func purpose(for entries: [URL]) -> CompareFilesWindowController.Purpose? {
    switch entries.count {
    case 1, 2: .compare
    case 3 where !entries.contains(where: \.hasDirectoryPath): .merge
    default: nil
    }
  }
}

/// Files dropped anywhere on the welcome window.
extension WelcomeWindowController: FileDropDelegate {
  /// What a drop of `entries` on the window does.
  enum Drop: Equatable {
    /// Opens the comparison of two files or two folders at once.
    case open(FileComparison)

    /// Puts the files in the fields of the sheet for the purpose, for the user to go on there.
    case fill(CompareFilesWindowController.Purpose)
  }

  /// What a drop of `entries` does: two files open at once with the older on the left, as the
  /// service Compare with Seamerge opens them, and two different folders in the order dropped;
  /// one file or folder, or two that do not go together, fill the sheet Compare Files, and three
  /// files the sheet Merge Files; `nil` for anything else.
  static func drop(of entries: [URL]) -> Drop? {
    guard let purpose = purpose(for: entries) else { return nil }
    if entries.count == 2 {
      var selection = FileSelection(kind: .diff)
      selection.fill([.left: entries[0], .right: entries[1]])
      if let comparison = selection.comparison {
        return .open(
          comparison.comparesFolders
            ? comparison : FileComparison(olderOf: entries[0], and: entries[1]))
      }
    }
    return .fill(purpose)
  }

  func operation(forDrag info: any NSDraggingInfo, onto slot: FileSlot?) -> NSDragOperation {
    guard
      window?.attachedSheet == nil, !isOpening,
      let entries = FileDrop.files(on: info.draggingPasteboard), let drop = Self.drop(of: entries)
    else {
      sidebar.dropArea.dropAction = nil
      return []
    }
    sidebar.dropArea.dropAction = Self.action(of: drop)
    return .copy
  }

  func acceptDrop(_ info: any NSDraggingInfo, onto slot: FileSlot?) -> Bool {
    defer { sidebar.dropArea.dropAction = nil }
    guard
      window?.attachedSheet == nil, !isOpening,
      let entries = FileDrop.files(on: info.draggingPasteboard), let drop = Self.drop(of: entries)
    else { return false }
    switch drop {
    case .open(let comparison):
      open(comparison)
    case .fill(let purpose):
      showFilesSheet(purpose) { sheet in sheet.fill(with: entries) }
    }
    return true
  }

  func dragDidEnd() {
    sidebar.dropArea.dropAction = nil
  }

  /// The words of the place to drop files while `drop` would be taken.
  private static func action(of drop: Drop) -> String {
    switch drop {
    case .open, .fill(.compare), .fill(.change):
      String(
        localized: "Drop to Compare", bundle: .module,
        comment: "Welcome window: the place to drop files while a drop would compare them.")
    case .fill(.merge):
      String(
        localized: "Drop to Merge", bundle: .module,
        comment: "Welcome window: the place to drop files while a drop would merge them.")
    }
  }
}
