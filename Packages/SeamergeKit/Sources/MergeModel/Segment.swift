/// The part of the result that belongs to one block.
///
/// The segments of a result lie back to back in the order of the blocks; where each one starts
/// follows from the lengths of those before it.
public struct Segment: Sendable, Hashable {
  /// How a segment came by its text.
  public enum State: Sendable, Hashable {
    /// An unchanged block that has the text it was loaded with.
    case untouched

    /// A changed block that has the source the merge took for it.
    case auto

    /// A block whose sources were chosen, other than those it was loaded with, or a conflict
    /// that was decided.
    case chosen

    /// A block whose text was edited by hand.
    case edited

    /// A conflict that awaits a decision; the segment holds a preview of A and B.
    case open
  }

  /// The length of the text in UTF-16 code units.
  public internal(set) var length: Int

  /// How the segment came by its text.
  public internal(set) var state: State

  /// The inputs whose text the segment takes, in the order their toggles were switched on.
  ///
  /// Inputs that share a toggle follow each other in the order base, A, B. The sources are empty
  /// for an open conflict and for a block that takes nothing. An edited segment keeps the sources
  /// it had before, so that its toggles still show them.
  public internal(set) var sources: [Role]

  /// Creates a segment.
  init(length: Int = 0, state: State, sources: [Role] = []) {
    self.length = length
    self.state = state
    self.sources = sources
  }

  /// Whether the segment takes its text from the same decision as `other`: neither is edited,
  /// and both have the same state and sources.
  ///
  /// Two such segments may still differ in length by a line ending that separates their text
  /// from the text that follows.
  func hasSameDecision(as other: Segment) -> Bool {
    state != .edited && other.state != .edited && state == other.state && sources == other.sources
  }
}
