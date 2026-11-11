/// An error in running the `git` command-line tool.
public enum GitError: Error, Sendable, Hashable {
  /// The executable could not be started.
  case launchFailed(executable: String, reason: String)

  /// The command did not finish within the time limit and was stopped.
  case timedOut(arguments: [String])

  /// The command ended with a status other than zero.
  ///
  /// `message` is what the command wrote to its standard error, without surrounding whitespace.
  case failed(arguments: [String], status: Int32, message: String)
}
