import Foundation
import MergeModel

/// The bytes of the files that a window compares, as far as it knows them on disk: as it read,
/// wrote or kept them last.
///
/// A file whose text in the window differs from these bytes has changes that are not saved. The
/// window notes the bytes before the first copy changes a file, when it reads a file anew, saves
/// it, or keeps its own version over a change that another app made, never when it changes the
/// text itself, as a copy, its undo and a switch of the comparison mode do. Going back with undo
/// past the bytes saved last thus makes the file count as changed again. A file the window knows
/// nothing of counts as unchanged.
struct FilesOnDisk {
  private var bytes: [URL: Data] = [:]

  /// The bytes the window knows the file at `url` holds on disk, or `nil` if it knows none.
  subscript(url: URL) -> Data? {
    bytes[url]
  }

  /// Notes that the file at `url` holds `bytes` on disk.
  mutating func note(_ bytes: Data, at url: URL) {
    self.bytes[url] = bytes
  }

  /// Notes what each file of `files` read from disk holds there.
  mutating func noteRead(_ files: some Sequence<SourceFile>) {
    for file in files {
      if let url = file.url {
        bytes[url] = file.bytes
      }
    }
  }

  /// Forgets what the files of `files` hold on disk, as after the window read them anew and holds
  /// no changes of them; the bytes of a file that the window shows count as on disk until it
  /// notes others.
  mutating func forget(_ files: some Sequence<SourceFile>) {
    for file in files {
      if let url = file.url {
        bytes[url] = nil
      }
    }
  }

  /// Whether `file`, as the window shows it, differs from what its file holds on disk.
  func hasChanges(_ file: SourceFile) -> Bool {
    guard let url = file.url, let known = bytes[url] else { return false }
    return known != file.bytes
  }
}
