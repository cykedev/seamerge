import Foundation
import MergeModel

/// Why the files of a session cannot be opened in a window.
public enum SessionLoadingError: LocalizedError, Equatable {
  /// The file cannot be read.
  case unreadableFile(URL)

  /// The file is not text.
  case binaryFile(URL)

  /// The files are too large to compare in memory.
  case filesTooLarge

  /// The comparison failed for another reason.
  case comparisonFailed

  /// Why the comparison of `files`, the files of each role, failed.
  init(_ error: MergeModelError, files: [Role: SessionFile]) {
    self =
      switch error {
      case .binaryInput(let role): files[role].map { .binaryFile($0.url) } ?? .comparisonFailed
      case .inputTooLarge, .outOfMemory: .filesTooLarge
      case .comparisonFailed, .unrepresentableText, .writingFailed: .comparisonFailed
      }
  }

  /// What went wrong, naming the file where one is to blame.
  public var errorDescription: String? {
    switch self {
    case .unreadableFile(let url):
      String(
        localized: "Seamerge can’t read “\(url.lastPathComponent)”.",
        bundle: .module, comment: "Alert: a file of a merge or comparison cannot be read.")
    case .binaryFile(let url):
      String(
        localized: "“\(url.lastPathComponent)” isn’t a text file.",
        bundle: .module, comment: "Alert: a file of a merge or comparison is binary.")
    case .filesTooLarge:
      String(
        localized: "The files are too large to compare.",
        bundle: .module, comment: "Alert: the files of a merge or comparison do not fit in memory.")
    case .comparisonFailed:
      String(
        localized: "Seamerge couldn’t compare the files.",
        bundle: .module, comment: "Alert: the comparison of the files of a session failed.")
    }
  }

  /// What to do next.
  public var recoverySuggestion: String? {
    switch self {
    case .unreadableFile:
      String(
        localized: "Check that the file exists and that you may read it, then try again.",
        bundle: .module, comment: "Alert: what to do when a file cannot be read.")
    case .binaryFile:
      String(
        localized: "Seamerge works with text. Use the app that made the file instead.",
        bundle: .module, comment: "Alert: what to do with a binary file.")
    case .filesTooLarge:
      String(
        localized: "Quit other apps to free memory, then try again.",
        bundle: .module, comment: "Alert: what to do when the files of a session are too large.")
    case .comparisonFailed:
      String(
        localized: "Try again. If it fails again, use another tool for these files.",
        bundle: .module, comment: "Alert: what to do when the comparison of the files failed.")
    }
  }
}
