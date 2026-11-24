import FolderCompare
public import Foundation
import GitSupport
import MergeModel
import os

/// A patch that a window shows, kept as files: the two sides of each of its files, built from
/// its hunks, each in a folder of its own.
///
/// Nothing in such a window is written: the sides are copies, which go with the window, and the
/// window has no file to save or to open elsewhere. No list of recent comparisons keeps it.
public struct PatchCopy: Sendable {
  /// A file of the patch, as the window compares it.
  struct File: Sendable {
    /// The older side, `/dev/null` for a file the patch adds.
    let old: SessionFile

    /// The newer side, `/dev/null` for a file the patch deletes.
    let new: SessionFile

    /// The path the list and the headers name the file by: the newer one, or the older one for
    /// a deleted file.
    let path: String
  }

  /// The folder that holds the copy.
  let folder: URL

  /// The name of the file the patch was read from, without its folders, or `nil` for a patch
  /// from standard input.
  let fileName: String?

  /// The files of the patch, in its order.
  let files: [File]

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// The title of a window that shows the patch: the name of its file, or Patch.
  var title: String {
    fileName
      ?? String(
        localized: "Patch", bundle: .module,
        comment: "The title of a window that shows a patch read from standard input.")
  }

  /// Whether the file at `url` is a side of the copy.
  func holds(_ url: URL) -> Bool {
    let folder = folder.standardizedFileURL.pathComponents
    let components = url.standardizedFileURL.pathComponents
    return components.count > folder.count && components.starts(with: folder)
  }

  /// The file of the patch at `index` as a file of a window that compares several, numbered in
  /// the order of the patch.
  func collectedFile(at index: Int) -> CollectedFile {
    let file = files[index]
    return CollectedFile(
      old: file.old, new: file.new,
      difftool: DifftoolContext(
        path: file.path, filePosition: FilePosition(number: index + 1, count: files.count)))
  }

  /// Whether the patch has no file to show, as one that changes nothing.
  public var isEmpty: Bool {
    files.isEmpty
  }

  /// Removes the copy with its folder, as the window that shows it does when it closes; for a
  /// copy that no window takes.
  public func remove() {
    guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
    do {
      try FileManager.default.removeItem(at: folder)
    } catch {
      Self.logger.error("Cannot remove the copy of a patch: \(error, privacy: .public)")
    }
  }
}

extension PatchCopy: Hashable {
  /// Two copies are the same if they lie in the same folder.
  public static func == (lhs: PatchCopy, rhs: PatchCopy) -> Bool {
    lhs.folder == rhs.folder
  }

  /// Hashes the folder, which tells a copy apart; the sides would take long to hash.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(folder)
  }
}
