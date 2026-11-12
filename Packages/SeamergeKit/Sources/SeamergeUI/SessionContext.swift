import Foundation
import GitSupport

/// What the window knows about a session besides its files: where the result of a merge goes,
/// and what Git is doing.
public struct SessionContext: Sendable, Hashable {
  /// The file the result of a merge is written to, if there is one; the window is titled after
  /// it.
  public var resultURL: URL?

  /// What Git is doing, if Git started the merge: the names and roles of the sides, the commits
  /// they come from and the progress of the operation.
  public var git: GitContext?

  /// What Git says about a comparison, if `git difftool` started it: the path of the file, what
  /// each side is, and which file of the run it is.
  public var difftool: DifftoolContext?

  /// Creates a context; without arguments, one that knows nothing beyond the files.
  public init(resultURL: URL? = nil, git: GitContext? = nil, difftool: DifftoolContext? = nil) {
    self.resultURL = resultURL
    self.git = git
    self.difftool = difftool
  }
}
