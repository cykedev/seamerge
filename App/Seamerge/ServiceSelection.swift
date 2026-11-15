import Foundation
import SeamergeUI

/// What the service Compare with Seamerge does with the files and folders selected in the
/// Finder.
///
/// The system shows the service for any selection of files and folders, so the app sorts out
/// what it can compare: two files or two folders open at once, the older file on the left; one
/// entry or three files go into the window Compare Files, where the user chooses the next file or
/// sees the roles before a merge; anything else gets a sentence there.
enum ServiceSelection: Equatable {
  /// One file or folder, to be compared with the one the user chooses next.
  case one(URL)

  /// Two files or two folders, compared at once.
  case comparison(FileComparison)

  /// Three files, in the order the Finder gave them, to be merged once their roles are seen.
  case threeFiles([URL])

  /// More than three entries, or files and folders together.
  case unsupported

  /// Sorts out the files and folders of `urls`; an entry that cannot be looked at counts as a
  /// file, which opening it then reports.
  init(_ urls: [URL]) {
    let entries = urls.map(Entry.init)
    let folders = entries.filter(\.isFolder).map(\.url)
    switch (entries.count, folders.count) {
    case (1, _):
      self = .one(entries[0].url)
    case (2, 0):
      let (first, second) = (entries[0], entries[1])
      // Files of the same age, or of an age they do not tell, keep the order of the Finder.
      let isSecondOlder =
        if let firstDate = first.modified, let secondDate = second.modified {
          secondDate < firstDate
        } else {
          false
        }
      let (older, newer) = isSecondOlder ? (second, first) : (first, second)
      self = .comparison(FileComparison(left: older.url, right: newer.url))
    case (2, 2):
      self = .comparison(FileComparison(folders: FolderPair(left: folders[0], right: folders[1])))
    case (3, 0):
      self = .threeFiles(entries.map(\.url))
    default:
      self = .unsupported
    }
  }

  /// A selected file or folder as the app takes it.
  private struct Entry {
    /// The file, or the folder as a directory path.
    let url: URL

    /// Whether the entry is a folder.
    let isFolder: Bool

    /// When the file was last changed, if it says.
    let modified: Date?

    init(_ url: URL) {
      var isDirectory: ObjCBool = false
      let path = url.path(percentEncoded: false)
      isFolder =
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        && isDirectory.boolValue
      self.url = URL(filePath: path, directoryHint: isFolder ? .isDirectory : .notDirectory)
      do {
        modified = try url.resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate
      } catch {
        // A file that does not say when it changed keeps its place in the selection.
        modified = nil
      }
    }
  }
}
