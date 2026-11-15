import Foundation
import MergeModel

/// Why the patch of a window could not be made or written.
enum PatchError: LocalizedError, Equatable {
  /// The files could not be compared byte for byte, for the reason given.
  case comparisonFailed(SessionLoadingError)

  /// The file of the patch could not be written, for the reason the file system gives.
  case writingFailed(reason: String)

  /// Why the comparison for a patch failed.
  init(_ error: MergeModelError) {
    self = .comparisonFailed(SessionLoadingError(error, files: [:]))
  }

  /// What went wrong.
  var errorDescription: String? {
    switch self {
    case .comparisonFailed(let error): error.errorDescription
    case .writingFailed(let reason): reason
    }
  }

  /// What to do next.
  var recoverySuggestion: String? {
    switch self {
    case .comparisonFailed(let error):
      error.recoverySuggestion
    case .writingFailed:
      String(
        localized: "Choose another folder, then export again.", bundle: .module,
        comment: "Sheet after exporting a patch failed: what to do next.")
    }
  }
}
