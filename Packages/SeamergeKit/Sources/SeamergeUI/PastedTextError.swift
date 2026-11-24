import Foundation

/// Why text from the clipboard could not be put in a field.
enum PastedTextError: Error, Sendable, Hashable, LocalizedError {
  /// The copy of the text could not be written to the caches folder.
  case cannotKeep

  var errorDescription: String? {
    String(
      localized: "Seamerge can’t keep the text from the clipboard.", bundle: .module,
      comment: "Alert: text pasted into a field of Compare Files could not be written to disk.")
  }

  var recoverySuggestion: String? {
    String(
      localized: "Check that your disk has free space, then paste again.", bundle: .module,
      comment: "Alert: what to do when pasted text could not be written to disk.")
  }
}
