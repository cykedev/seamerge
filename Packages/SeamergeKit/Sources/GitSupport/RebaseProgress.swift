/// How far a rebase has come.
public struct RebaseProgress: Sendable, Hashable {
  /// The name of the commit the rebase moves the commits onto, such as a branch.
  public var targetName: SideName

  /// The number of the commit being applied, counted from 1.
  public var commitNumber: Int

  /// How many commits the rebase applies in all.
  public var commitCount: Int
}
