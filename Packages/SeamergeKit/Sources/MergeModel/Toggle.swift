/// A switch that adds the text of one or more inputs to a block of the result, or takes it out.
///
/// Inputs with the same text in a block share a toggle, so a block has as many toggles as it has
/// different versions. Only identical bytes count as the same text: versions that differ only in
/// whitespace the comparison ignores keep a toggle each.
public struct Toggle: Sendable, Hashable {
  /// What switching a toggle on takes over.
  public enum Kind: Sendable, Hashable {
    /// The lines of the inputs.
    case version

    /// The removal of the base's lines: the inputs of the toggle have no lines in the block.
    case deletion
  }

  /// The inputs that share the toggle, in the order base, A, B.
  public let roles: [Role]

  /// What switching the toggle on takes over.
  public let kind: Kind

  /// The text the inputs of the toggle have in the block.
  let text: String

  /// Whether switching the toggle on empties the block and switches the other toggles off.
  ///
  /// That holds for every toggle without text: following a deletion means taking nothing else,
  /// and taking nothing in addition to something has no effect.
  public var isExclusive: Bool { text.isEmpty }
}
