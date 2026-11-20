public import FolderCompare
public import Foundation
public import GitSupport

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

  /// The folders whose files the window compares, if it compares two folders.
  public var folders: FolderPair?

  /// Who waits for the end of a merge and hears how it ended, if anyone does.
  ///
  /// Words about what Git does with the file stand only where Git waits; files that lie in a
  /// repository, which ``git`` describes, are no sign of that.
  public var waitingCaller: WaitingCaller?

  /// Creates a context; without arguments, one that knows nothing beyond the files.
  public init(
    resultURL: URL? = nil, git: GitContext? = nil, difftool: DifftoolContext? = nil,
    waitingCaller: WaitingCaller? = nil, folders: FolderPair? = nil
  ) {
    self.resultURL = resultURL
    self.git = git
    self.difftool = difftool
    self.waitingCaller = waitingCaller
    self.folders = folders
  }
}

/// Who waits for the end of a merge.
public enum WaitingCaller: Sendable, Hashable {
  /// A command on the command line, such as `seamerge merge` typed by hand; it ends with success
  /// if the merge was saved.
  case commandLine

  /// Git, which ran the command and waits for it, as `git mergetool` does: it takes the file as
  /// resolved once the merge is saved, and puts back the file it had before when it is not.
  case git
}
