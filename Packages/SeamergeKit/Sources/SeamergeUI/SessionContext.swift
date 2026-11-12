import Foundation
import GitSupport

/// What the window knows about a merge besides its files: where the result goes and what Git is
/// doing.
public struct SessionContext: Sendable, Hashable {
  /// The file the result is written to, if there is one; the window is titled after it.
  public var resultURL: URL?

  /// What Git is doing, if Git started the merge: the names and roles of the sides, the commits
  /// they come from and the progress of the operation.
  public var git: GitContext?

  /// Creates a context; without arguments, one that knows nothing beyond the files.
  public init(resultURL: URL? = nil, git: GitContext? = nil) {
    self.resultURL = resultURL
    self.git = git
  }
}
