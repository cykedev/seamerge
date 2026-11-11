/// A Git operation that stops when a file has conflicts.
public enum GitOperation: Sendable, Hashable {
  /// `git merge`.
  case merge

  /// `git rebase`, with either backend.
  case rebase

  /// `git cherry-pick`.
  case cherryPick

  /// `git revert`.
  case revert

  /// `git stash pop` or `git stash apply`.
  case stash
}
