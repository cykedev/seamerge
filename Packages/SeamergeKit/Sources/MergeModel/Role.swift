/// One of the inputs of a session.
///
/// In a merge, A is the incoming side and B the own side; in a comparison, A is the older file
/// on the left and B the newer file on the right, and there is no base.
public enum Role: Sendable, Hashable, CaseIterable {
  /// The common ancestor of A and B in a merge.
  case base

  /// The incoming side of a merge, or the older file of a comparison.
  case a

  /// The own side of a merge, or the newer file of a comparison.
  case b
}
