import Foundation

/// Which files of a collection its list shows: those whose sides differ, or that cannot be
/// compared.
struct FileFilter: Equatable {
  /// Whether the list shows `file`.
  func includes(_ file: CollectedFile) -> Bool {
    file.change != .identical
  }
}
