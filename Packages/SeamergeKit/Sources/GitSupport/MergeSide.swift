/// One side of a merge as the header above its pane names it.
public struct MergeSide: Sendable, Hashable {
  /// What the side is called, or `nil` if nothing names it.
  public var name: SideName?

  /// What the side stands for in the operation, or `nil` if the operation gives it no role.
  public var role: SideRole?

  /// The commit the side comes from, if it is known.
  public var commit: CommitDetails?

  /// Creates a side.
  public init(name: SideName? = nil, role: SideRole? = nil, commit: CommitDetails? = nil) {
    self.name = name
    self.role = role
    self.commit = commit
  }
}

/// The name of one side of a merge.
public enum SideName: Sendable, Hashable {
  /// A name Git knows the side by: a branch, a tag, another reference, or a label from a conflict
  /// marker.
  case reference(String)

  /// A commit, by its abbreviated hash.
  ///
  /// - Parameters:
  ///   - abbreviatedHash: The abbreviated hash of the commit.
  ///   - subject: The first line of its message, if it belongs in the name.
  ///   - branch: The branch the commit is on, if it belongs in the name.
  case commit(abbreviatedHash: String, subject: String?, branch: String?)

  /// The changes of a stash.
  case stash
}

/// What a side of a merge stands for in the Git operation.
public enum SideRole: Sendable, Hashable {
  /// The branch being merged in.
  case incoming

  /// The branch the user is on.
  case yours

  /// The user's own commit, being moved by a rebase.
  case yourCommit

  /// The commit a rebase moves the user's commits onto.
  case rebaseTarget

  /// The commit being cherry-picked.
  case cherryPickedCommit

  /// The commit being reverted.
  case revertedCommit
}
