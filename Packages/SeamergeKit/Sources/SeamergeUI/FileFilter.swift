import Foundation

/// Which files of a collection its list shows: identical files only on request.
struct FileFilter: Equatable {
  /// Whether files whose sides hold the same bytes are listed.
  var showsIdenticalFiles = false

  /// Whether the list shows `file`.
  func includes(_ file: CollectedFile) -> Bool {
    file.change != .identical || showsIdenticalFiles
  }
}
