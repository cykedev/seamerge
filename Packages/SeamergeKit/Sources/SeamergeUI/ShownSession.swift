import MergeModel

/// A session as a window shows it: a comparison of two files, or a merge with its result as it
/// stands.
///
/// Only a merge has a result, and the merge is the session of its result.
enum ShownSession: Sendable {
  /// A comparison of two files, which has no result.
  case comparison(Session)

  /// A merge, with its result as it stands.
  case merge(ResultState)

  /// `session` as loaded: a merge with every conflict open and every other change taken as the
  /// merge takes it, the preview of a conflict showing the note of `removalNotes` in place of
  /// the lines of a side that removed them.
  init(loading session: Session, removalNotes: [Role: String]) {
    switch session.kind {
    case .merge: self = .merge(ResultState(session: session, removalNotes: removalNotes))
    case .diff: self = .comparison(session)
    }
  }

  /// The session.
  var session: Session {
    switch self {
    case .comparison(let session): session
    case .merge(let result): result.document.session
    }
  }

  /// The result of a merge, or `nil` for a comparison.
  var result: ResultState? {
    switch self {
    case .comparison: nil
    case .merge(let result): result
    }
  }
}
