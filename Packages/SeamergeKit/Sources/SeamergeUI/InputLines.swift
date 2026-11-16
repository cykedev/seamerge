import MergeModel
import PaneKit

/// The lines of the inputs of a session as the panes show them without filler rows, and how
/// each of them ends: worked out once for a comparison, when a pane first needs them, and kept
/// for the next comparison of the same files.
struct InputLines: Sendable {
  /// The session whose lines these are.
  private(set) var session: Session

  /// The text of each input without filler rows, as far as it is worked out.
  private var texts: [Role: DisplayText] = [:]

  /// How each line of each input ends, as far as it is worked out.
  private var endings: [Role: [LineEnding]] = [:]

  /// The lines of the inputs of `session`, none worked out yet.
  init(session: Session) {
    self.session = session
  }

  /// The lines of the inputs of `session`, another comparison of files that may be the same,
  /// keeping what is worked out for each file that has the same bytes and lines in both.
  ///
  /// The lines of a file are the same in two comparisons that split it into as many lines,
  /// since one comparison mode ends lines at more places than another or at the same.
  func carried(to session: Session) -> InputLines {
    var carried = InputLines(session: session)
    for role in session.roles where keepsLines(of: role, in: session) {
      carried.texts[role] = texts[role]
      carried.endings[role] = endings[role]
    }
    return carried
  }

  /// Takes what `other`, the lines of the same session, has worked out beyond these.
  mutating func take(_ other: InputLines) {
    texts.merge(other.texts) { kept, _ in kept }
    endings.merge(other.endings) { kept, _ in kept }
  }

  /// Whether the input of `role` has the same bytes and lines in `other` as in this session.
  private func keepsLines(of role: Role, in other: Session) -> Bool {
    guard let file = session.file(for: role), let otherFile = other.file(for: role) else {
      return false
    }
    return session.rowLayout.lineCount(in: role) == other.rowLayout.lineCount(in: role)
      && file.bytes == otherFile.bytes
  }

  /// The text of the input of `role` without filler rows.
  ///
  /// - Precondition: `role` takes part in the session.
  mutating func text(of role: Role) -> DisplayText {
    if let text = texts[role] {
      return text
    }
    guard let text = session.rowLayout.lineText(for: role) else {
      preconditionFailure("The session has no input \(role)")
    }
    texts[role] = text
    return text
  }

  /// How each line of the input of `role` ends.
  ///
  /// - Precondition: `role` takes part in the session.
  mutating func endings(of role: Role) -> [LineEnding] {
    if let endings = endings[role] {
      return endings
    }
    guard let file = session.file(for: role) else {
      preconditionFailure("The session has no input \(role)")
    }
    let lineEndings = PaneContent.lineEndings(
      of: file, lineCount: session.rowLayout.lineCount(in: role))
    endings[role] = lineEndings
    return lineEndings
  }
}
