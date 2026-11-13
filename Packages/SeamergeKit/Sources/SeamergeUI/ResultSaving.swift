import Foundation
import MergeModel

/// What a window knows about the file of its result: how it is written, where it goes, and what
/// was saved there last.
struct ResultSaving {
  /// How the result is written.
  var format: ResultFormat

  /// Where Save writes the result, or `nil` until the user chooses a place.
  var url: URL?

  /// The result as it was saved last, or `nil` if it was never saved; a merge that Git started
  /// counts as unsaved from the start, since its file holds conflict markers.
  var saved: SavedResult?

  /// The bytes of the file at ``url`` as the window knows them: as it found, wrote or accepted
  /// them last, which tells a change by another app from its own writing.
  var diskBytes: Data?

  /// The saving of the result of `session`, which goes to `url` if there is one; a result
  /// without one counts as saved as it was loaded, like a new document.
  init(result: ResultState, session: Session, url: URL?) {
    format = ResultFormat(resultOf: session)
    self.url = url
    saved = url == nil ? SavedResult(result, session: session, format: format) : nil
    diskBytes = url.flatMap { FileManager.default.contents(atPath: $0.path(percentEncoded: false)) }
  }

  /// Whether `result` of `session` differs from what was saved last.
  func isEdited(_ result: ResultState, session: Session) -> Bool {
    saved != SavedResult(result, session: session, format: format)
  }
}

/// What makes up a saved result: the text with the decisions of its blocks, the files it was
/// merged from, and its format.
struct SavedResult: Equatable {
  let text: String
  let segments: [Segment]
  let options: ComparisonOptions
  let sources: [Data?]
  let format: ResultFormat

  init(_ result: ResultState, session: Session, format: ResultFormat) {
    text = result.text
    segments = result.document.segments
    options = session.options
    sources = Role.allCases.map { session.file(for: $0)?.bytes }
    self.format = format
  }

  /// Equal results write the same bytes; texts are compared byte for byte rather than by
  /// canonical equivalence, which would take a composed and a decomposed é as the same.
  static func == (lhs: SavedResult, rhs: SavedResult) -> Bool {
    lhs.segments == rhs.segments && lhs.options == rhs.options && lhs.format == rhs.format
      && lhs.text.utf8.count == rhs.text.utf8.count
      && lhs.text.utf8.elementsEqual(rhs.text.utf8) && lhs.sources == rhs.sources
  }
}
