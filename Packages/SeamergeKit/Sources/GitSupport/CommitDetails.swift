public import Foundation

/// The facts about a commit that tell the user where a side comes from.
public struct CommitDetails: Sendable, Hashable {
  /// The full hash.
  public var hash: String

  /// The shortest unique prefix of the hash, at least as long as Git abbreviates hashes.
  public var abbreviatedHash: String

  /// The name of the author, after Git's mailmap.
  public var authorName: String

  /// When the author made the commit.
  public var authorDate: Date

  /// The first line of the commit message.
  public var subject: String

  /// Creates the facts about a commit.
  public init(
    hash: String, abbreviatedHash: String, authorName: String, authorDate: Date, subject: String
  ) {
    self.hash = hash
    self.abbreviatedHash = abbreviatedHash
    self.authorName = authorName
    self.authorDate = authorDate
    self.subject = subject
  }

  /// The format for `git show` that ``init(showOutput:)`` reads.
  static let showFormat = "%H%x00%h%x00%aN%x00%at%x00%s"

  /// Reads the output of `git show` in ``showFormat``, or returns `nil` if it is not in that form.
  init?(showOutput: String) {
    let fields = showOutput.split(separator: "\0", omittingEmptySubsequences: false)
    guard fields.count == 5, let seconds = TimeInterval(fields[3]) else { return nil }
    self.init(
      hash: String(fields[0]), abbreviatedHash: String(fields[1]), authorName: String(fields[2]),
      authorDate: Date(timeIntervalSince1970: seconds), subject: String(fields[4]))
  }
}
