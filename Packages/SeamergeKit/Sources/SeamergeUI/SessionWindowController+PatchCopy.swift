public import AppKit
import FolderCompare
import GitSupport
import MergeModel

extension SessionWindowController {
  /// Opens a window that shows the patch kept in `copy`: a comparison of the sides of its file,
  /// or, for several files, a window that lists them, each drawn and compared as `settings`
  /// say; the copy goes when the window closes.
  ///
  /// Nothing in the window can be changed: its sides are never written, and the window has no
  /// file to save or to open elsewhere. A file that the patch shows no lines of, as a binary
  /// file, says so in place of its lines.
  ///
  /// - Precondition: The patch has a file.
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if not even the headers of its first
  ///   file can be made; the copy stays, for the caller to remove.
  public static func openPatch(
    _ copy: PatchCopy, undoManager: UndoManager, settings: UserSettings
  ) async throws(SessionLoadingError) -> SessionWindowController {
    precondition(!copy.files.isEmpty, "A window shows a patch with a file")
    guard copy.files.count == 1, let file = copy.files.first else {
      let collection = FileCollection(
        origin: CollectionOrigin(repository: copy.folder.path(percentEncoded: false), run: nil),
        expectedCount: copy.files.count)
      for index in copy.files.indices {
        collection.add(copy.collectedFile(at: index))
      }
      return try await SessionWindowController(
        collection: collection, undoManager: undoManager, settings: settings, patch: copy)
    }
    let context = SessionContext(
      difftool: DifftoolContext(path: file.path, filePosition: FilePosition(number: 1, count: 1)),
      patch: copy)
    do {
      return try await openDiff(
        old: file.old, new: file.new, mode: settings.comparisonMode,
        ignoring: settings.ignoreRules, context: context,
        undoManager: undoManager, settings: settings)
    } catch {
      return try await SessionWindowController(
        unavailable: UnavailableComparison(old: file.old, new: file.new, reason: error),
        context: context, undoManager: undoManager, settings: settings)
    }
  }
}
