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

  /// Creates a context from what is known about a comparison, such as what the command-line tool
  /// found out and handed over.
  public init(
    path: String, leftRole: DiffSideRole = .before, rightRole: DiffSideRole = .after,
    filePosition: FilePosition? = nil
  ) {
    self.path = path
    self.leftRole = leftRole
    self.rightRole = rightRole
    self.filePosition = filePosition
  }

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

  /// The path of the compared file relative to `workingDirectory`, when the caller did not
  /// name it: the path of the one side that is a file in `workingDirectory`, while the other side
  /// is a temporary copy or missing, as Tower passes the sides of a change in the working tree.
  ///
  /// Returns `nil` if both sides or neither are such a file. `temporaryDirectory` is the
  /// temporary folder of the user, where Git writes its copies.
  public static func inferredPath(
    leftFile: URL, rightFile: URL, workingDirectory: URL,
    temporaryDirectory: URL = FileManager.default.temporaryDirectory
  ) -> String? {
    let sides = [leftFile, rightFile].map {
      ($0, FileOrigin(url: $0, temporaryDirectory: temporaryDirectory))
    }
    let ordinary = sides.filter { $0.1 == .ordinary }
    guard ordinary.count == 1, let file = ordinary.first?.0 else { return nil }
    let folder = canonicalPath(of: workingDirectory)
    let path = canonicalPath(of: file)
    let prefix = folder.hasSuffix("/") ? folder : folder + "/"
    guard path.hasPrefix(prefix) else { return nil }
    return String(path.dropFirst(prefix.count))
  }

  private static func canonicalPath(of url: URL) -> String {
    FileOrigin.canonicalPath(of: url)
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

  /// Creates the position of file `number`, counted from 1, among `count` files.
  public init(number: Int, count: Int) {
    self.number = number
    self.count = count
  }

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
