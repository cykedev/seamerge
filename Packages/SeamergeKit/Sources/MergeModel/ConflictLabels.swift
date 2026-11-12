/// The names written after the conflict markers of an open conflict.
public struct ConflictLabels: Sendable, Hashable {
  /// Written after `>>>>>>>`, the marker that closes A's lines.
  public var a: String

  /// Written after `|||||||`, the marker that opens the base's lines.
  public var base: String

  /// Written after `<<<<<<<`, the marker that opens B's lines.
  public var b: String

  /// Creates labels for the three markers that carry one.
  public init(a: String, base: String, b: String) {
    self.a = a
    self.base = base
    self.b = b
  }
}
