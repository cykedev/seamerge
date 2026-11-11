import Foundation

/// What Git passes to the tool when it compares a file through `git difftool`.
///
/// Git names neither side; both carry the path of the file, and a side that is the file in the
/// working tree is the working copy.
public struct DifftoolContext: Sendable, Hashable {
  /// The path of the file relative to the top of the working tree, as Git passes it in `MERGED`.
  public var path: String

  /// What the left side is: the file before the change, or the working copy.
  public var leftRole: DiffSideRole

  /// What the right side is: the file after the change, or the working copy.
  public var rightRole: DiffSideRole

  /// Which file of the comparison this is, if Git tells.
  public var filePosition: FilePosition?

  /// Names both sides of a comparison.
  ///
  /// A side is the working copy if its file is the file at `path` in `workingDirectory`, which
  /// Git makes the top of the working tree before it starts the tool. Git passes the other sides
  /// as temporary files, or as `/dev/null` for a file that does not exist on that side.
  ///
  /// - Parameters:
  ///   - path: The path Git passes as `MERGED`.
  ///   - leftFile: The file Git passes as `LOCAL`.
  ///   - rightFile: The file Git passes as `REMOTE`.
  ///   - workingDirectory: The directory Git starts the tool in.
  ///   - environment: The environment Git starts the tool with; `GIT_DIFF_PATH_COUNTER` and
  ///     `GIT_DIFF_PATH_TOTAL` give the position of the file.
  public static func detect(
    path: String,
    leftFile: URL,
    rightFile: URL,
    workingDirectory: URL,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> DifftoolContext {
    let workingCopy = canonicalPath(of: workingDirectory.appending(path: path))
    return DifftoolContext(
      path: path,
      leftRole: canonicalPath(of: leftFile) == workingCopy ? .workingCopy : .before,
      rightRole: canonicalPath(of: rightFile) == workingCopy ? .workingCopy : .after,
      filePosition: FilePosition(environment: environment))
  }

  private static func canonicalPath(of url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
  }
}

/// What one side of a comparison through `git difftool` is.
public enum DiffSideRole: Sendable, Hashable {
  /// The file before the change.
  case before

  /// The file after the change.
  case after

  /// The file in the working tree, which the user can edit.
  case workingCopy
}

/// The position of a file among the files of one `git difftool` run.
public struct FilePosition: Sendable, Hashable {
  /// The number of the file, counted from 1.
  public var number: Int

  /// How many files the run compares.
  public var count: Int

  /// Reads the position from `GIT_DIFF_PATH_COUNTER` and `GIT_DIFF_PATH_TOTAL`, or returns `nil`
  /// if either is missing or the two do not fit together.
  init?(environment: [String: String]) {
    guard let number = environment["GIT_DIFF_PATH_COUNTER"].flatMap({ Int($0) }),
      let count = environment["GIT_DIFF_PATH_TOTAL"].flatMap({ Int($0) }),
      count >= 1, (1...count).contains(number)
    else { return nil }
    self.number = number
    self.count = count
  }
}
