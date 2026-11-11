import Foundation
import os

/// A Git repository as seen from a directory inside its working tree.
///
/// Every query runs `git` once or reads one file in the Git directory. A query that fails, takes
/// too long or finds the repository in an unexpected state returns `nil` and is logged; the
/// caller then falls back to the next source of the same fact.
struct Repository {
  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "GitSupport")

  private let git: Git
  private let workingDirectory: URL

  /// The Git directory, which holds the state of an operation in progress.
  let gitDirectory: URL

  /// Opens the repository that contains `workingDirectory`, or returns `nil` if there is none.
  init?(git: Git, workingDirectory: URL) {
    self.git = git
    self.workingDirectory = workingDirectory
    guard let path = Self.query(git, ["rev-parse", "--absolute-git-dir"], in: workingDirectory)
    else { return nil }
    gitDirectory = URL(filePath: path, directoryHint: .isDirectory)
  }

  /// The operation in progress, as the files in the Git directory show it.
  ///
  /// A stash leaves no such file, so it is not recognized here.
  var operation: GitOperation? {
    if isRebasing { return .rebase }
    if exists("MERGE_HEAD") { return .merge }
    if exists("CHERRY_PICK_HEAD") { return .cherryPick }
    if exists("REVERT_HEAD") { return .revert }
    return nil
  }

  /// Whether a rebase is in progress, with either backend.
  ///
  /// `git am` uses the directory of the older backend as well; a file `applying` marks it.
  private var isRebasing: Bool {
    exists("rebase-merge") || (exists("rebase-apply") && !exists("rebase-apply/applying"))
  }

  /// The first line of a file in the Git directory, without surrounding whitespace.
  func firstLine(of name: String) -> String? {
    let url = gitDirectory.appending(path: name)
    guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
    let text = String(decoding: data, as: UTF8.self)
    let line = text.prefix { $0 != "\n" }.trimmingCharacters(in: .whitespaces)
    return line.isEmpty ? nil : line
  }

  /// The commit a file in the Git directory names, such as `MERGE_HEAD`, if it names one by its
  /// full hash.
  ///
  /// Only a hash is accepted, so that a damaged file never reaches `git` as an option.
  func commitHash(in name: String) -> String? {
    guard let line = firstLine(of: name), Self.isFullHash(line) else {
      if exists(name) { Self.logger.error("\(name, privacy: .public) holds no commit hash") }
      return nil
    }
    return line
  }

  /// A whole number in a file in the Git directory, such as `rebase-merge/msgnum`.
  func number(in name: String) -> Int? {
    firstLine(of: name).flatMap { Int($0) }
  }

  /// The short name of the branch `HEAD` is on, or `nil` if `HEAD` is detached.
  var currentBranch: String? {
    query(["symbolic-ref", "--quiet", "--short", "HEAD"])
  }

  /// The facts about a commit.
  ///
  /// - Parameter revision: A full hash or `HEAD`.
  func commitDetails(_ revision: String) -> CommitDetails? {
    let arguments = [
      "show", "--no-show-signature", "--no-color", "--no-patch",
      "--format=\(CommitDetails.showFormat)", revision,
    ]
    guard let output = query(arguments) else { return nil }
    guard let details = CommitDetails(showOutput: output) else {
      Self.logger.error("git show printed something other than the requested format")
      return nil
    }
    return details
  }

  /// A name for a commit that people recognize, such as a branch or a tag pointing near it.
  ///
  /// - Parameter hash: A full hash.
  func name(ofCommit hash: String) -> String? {
    query(["name-rev", "--name-only", "--no-undefined", hash])
  }

  /// The full hash of the best common ancestor of two commits.
  func mergeBase(_ first: String, _ second: String) -> String? {
    query(["merge-base", first, second])
  }

  /// The paths of the files with conflicts, relative to the top of the working tree.
  var conflictedPaths: Set<String>? {
    let arguments = ["diff", "--name-only", "--no-relative", "--diff-filter=U", "-z"]
    guard let output = query(arguments) else { return nil }
    return Set(output.split(separator: "\0").map(String.init))
  }

  /// The stages of the unmerged index entries of a file, or `nil` if it has none or Git cannot
  /// tell.
  ///
  /// - Parameter path: The path of the file relative to the top of the working tree. It is taken
  ///   literally, so that characters such as `*` in a file name match only themselves.
  func unmergedStages(ofPath path: String) -> Set<IndexStage>? {
    let pathspec = ":(top,literal)\(path)"
    guard let output = query(["ls-files", "--unmerged", "-z", "--", pathspec]) else { return nil }
    var stages: Set<IndexStage> = []
    // Each entry reads `<mode> <hash> <stage>\t<path>`.
    for entry in output.split(separator: "\0") {
      let fields = entry.prefix { $0 != "\t" }.split(separator: " ")
      guard fields.count == 3, let stage = Int(fields[2]).flatMap(IndexStage.init) else {
        Self.logger.error("git ls-files printed an entry in an unexpected form")
        return nil
      }
      stages.insert(stage)
    }
    return stages
  }

  /// The top directory of the working tree.
  var topLevel: URL? {
    query(["rev-parse", "--show-toplevel"]).map { URL(filePath: $0, directoryHint: .isDirectory) }
  }

  private func exists(_ name: String) -> Bool {
    FileManager.default.fileExists(atPath: gitDirectory.appending(path: name).path)
  }

  private func query(_ arguments: [String]) -> String? {
    Self.query(git, arguments, in: workingDirectory)
  }

  private static func query(_ git: Git, _ arguments: [String], in directory: URL) -> String? {
    do {
      let text = try git.text(arguments, in: directory)
      return text.isEmpty ? nil : text
    } catch {
      logger.debug("\(String(describing: error))")
      return nil
    }
  }

  private static func isFullHash(_ text: String) -> Bool {
    (text.count == 40 || text.count == 64)
      && text.allSatisfy { $0.isASCII && $0.isHexDigit && !$0.isUppercase }
  }
}

/// The stage of an index entry of a file with a conflict.
enum IndexStage: Int {
  /// The version of the common ancestor.
  case commonAncestor = 1

  /// The version of the current branch, `LOCAL`.
  case ours = 2

  /// The version being merged in, `REMOTE`.
  case theirs = 3
}
