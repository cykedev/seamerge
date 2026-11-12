import Foundation

extension SessionRequest {
  /// What Git is doing while it asks for a merge, as the headers and the subtitle show it.
  ///
  /// The sides follow `git mergetool`: ``remote`` is `REMOTE`, shown on the left, and ``local`` is
  /// `LOCAL`, shown on the right. In a rebase they are the other way round from a merge; the roles
  /// say so.
  public struct MergeContext: Sendable, Hashable, Codable {
    /// The operation in progress, or `nil` if none is recognized.
    public var operation: GitOperation?

    /// The side Git calls `REMOTE`.
    public var remote: Side

    /// The side Git calls `LOCAL`.
    public var local: Side

    /// The common ancestor.
    public var base: Side

    /// How far the rebase has come, if a rebase is in progress.
    public var rebaseProgress: RebaseProgress?

    /// How many files besides this one still have conflicts, or `nil` if it is not known.
    public var remainingConflictedFileCount: Int?

    /// Creates a context; without arguments, one that knows nothing.
    public init(
      operation: GitOperation? = nil,
      remote: Side = Side(),
      local: Side = Side(),
      base: Side = Side(),
      rebaseProgress: RebaseProgress? = nil,
      remainingConflictedFileCount: Int? = nil
    ) {
      self.operation = operation
      self.remote = remote
      self.local = local
      self.base = base
      self.rebaseProgress = rebaseProgress
      self.remainingConflictedFileCount = remainingConflictedFileCount
    }
  }

  /// A Git operation that stops when a file has conflicts.
  public enum GitOperation: String, Sendable, Hashable, Codable {
    /// `git merge`.
    case merge

    /// `git rebase`.
    case rebase

    /// `git cherry-pick`.
    case cherryPick

    /// `git revert`.
    case revert

    /// `git stash pop` or `git stash apply`.
    case stash
  }

  /// One side of a merge as the header above its pane names it.
  public struct Side: Sendable, Hashable, Codable {
    /// What the side is called, or `nil` if nothing names it.
    public var name: SideName?

    /// What the side stands for in the operation, or `nil` if it has no role.
    public var role: SideRole?

    /// The commit the side comes from, if it is known.
    public var commit: Commit?

    /// Creates a side.
    public init(name: SideName? = nil, role: SideRole? = nil, commit: Commit? = nil) {
      self.name = name
      self.role = role
      self.commit = commit
    }
  }

  /// The name of one side of a merge.
  public enum SideName: Sendable, Hashable, Codable {
    /// A name such as a branch, a tag or a label from the command line or a conflict marker.
    case reference(String)

    /// A commit, by its abbreviated hash, with its subject and branch if they belong in the name.
    case commit(abbreviatedHash: String, subject: String?, branch: String?)

    /// The changes of a stash.
    case stash

    private enum ReferenceCodingKeys: String, CodingKey {
      case _0 = "name"
    }
  }

  /// What a side of a merge stands for in the Git operation.
  public enum SideRole: String, Sendable, Hashable, Codable {
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

  /// The facts about a commit that the popover of a header shows.
  public struct Commit: Sendable, Hashable {
    /// The full hash.
    public var hash: String

    /// The abbreviated hash.
    public var abbreviatedHash: String

    /// The first line of the commit message.
    public var subject: String

    /// The name of the author.
    public var authorName: String

    /// When the author made the commit, to the second.
    public var authorDate: Date

    /// Creates the facts about a commit.
    public init(
      hash: String, abbreviatedHash: String, subject: String, authorName: String, authorDate: Date
    ) {
      self.hash = hash
      self.abbreviatedHash = abbreviatedHash
      self.subject = subject
      self.authorName = authorName
      self.authorDate = authorDate
    }
  }

  /// How far a rebase has come.
  public struct RebaseProgress: Sendable, Hashable, Codable {
    /// The name of the commit the rebase moves the commits onto.
    public var targetName: SideName

    /// The number of the commit being applied, counted from 1.
    public var commitNumber: Int

    /// How many commits the rebase applies in all.
    public var commitCount: Int

    /// Creates the progress of a rebase.
    public init(targetName: SideName, commitNumber: Int, commitCount: Int) {
      self.targetName = targetName
      self.commitNumber = commitNumber
      self.commitCount = commitCount
    }
  }
}

extension SessionRequest.Commit: Codable {
  private enum CodingKeys: String, CodingKey {
    case hash, abbreviatedHash, subject, authorName, authorDate
  }

  /// Decodes a commit whose date is written in ISO 8601.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    hash = try container.decode(String.self, forKey: .hash)
    abbreviatedHash = try container.decode(String.self, forKey: .abbreviatedHash)
    subject = try container.decode(String.self, forKey: .subject)
    authorName = try container.decode(String.self, forKey: .authorName)
    let date = try container.decode(String.self, forKey: .authorDate)
    do {
      authorDate = try Date(date, strategy: .iso8601)
    } catch {
      throw DecodingError.dataCorruptedError(
        forKey: .authorDate, in: container, debugDescription: "\(date) is not an ISO 8601 date.")
    }
  }

  /// Encodes a commit with its date in ISO 8601, whatever the date strategy of the encoder.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(hash, forKey: .hash)
    try container.encode(abbreviatedHash, forKey: .abbreviatedHash)
    try container.encode(subject, forKey: .subject)
    try container.encode(authorName, forKey: .authorName)
    try container.encode(authorDate.formatted(.iso8601), forKey: .authorDate)
  }
}
