import Foundation

/// A request from the command-line tool to the app to open a merge or a comparison.
///
/// The tool finds out what Git is doing and sends it along, so that the app shows it without
/// asking Git itself. File URLs in a request are absolute; a request with a relative path cannot
/// be decoded.
public enum SessionRequest: Sendable, Hashable {
  /// A three-way merge that writes its result into a file.
  case merge(Merge)

  /// A comparison of two files.
  case diff(Diff)

  /// The files of a merge and what Git is doing while it asks for the merge.
  public struct Merge: Sendable, Hashable {
    /// The common ancestor, or `nil` if there is none.
    public var base: URL?

    /// The version of the current branch, `LOCAL` in Git's terms.
    public var local: URL

    /// The version being merged in, `REMOTE` in Git's terms.
    public var remote: URL

    /// The file the result of the merge is written to.
    public var output: URL

    /// The operation and the names, roles and commits of the three sides.
    ///
    /// Names given on the command line are already in it: they win over everything Git says.
    public var context: MergeContext

    /// Whether Git runs the command that asks for the merge and waits for its end, as
    /// `git mergetool` does, which the command line says with `--from-git`.
    ///
    /// The files lying in a repository does not make a merge one that Git waits for.
    public var isRunByGit: Bool

    /// Creates the description of a merge.
    public init(
      base: URL?, local: URL, remote: URL, output: URL, context: MergeContext = MergeContext(),
      isRunByGit: Bool = false
    ) {
      self.base = base
      self.local = local
      self.remote = remote
      self.output = output
      self.context = context
      self.isRunByGit = isRunByGit
    }
  }

  /// The files of a comparison and what Git says about them.
  public struct Diff: Sendable, Hashable {
    /// The older file, shown on the left.
    public var left: URL

    /// The newer file, shown on the right.
    public var right: URL

    /// The path the comparison is shown under, if it differs from the paths of both files.
    ///
    /// Git compares temporary copies, so this is the path of the file in the repository.
    public var displayPath: String?

    /// The name given for the left file on the command line.
    public var leftLabel: String?

    /// The name given for the right file on the command line.
    public var rightLabel: String?

    /// What each side is, and which file of the run this is.
    public var context: DiffContext

    /// Creates the description of a comparison.
    public init(
      left: URL,
      right: URL,
      displayPath: String? = nil,
      leftLabel: String? = nil,
      rightLabel: String? = nil,
      context: DiffContext = DiffContext()
    ) {
      self.left = left
      self.right = right
      self.displayPath = displayPath
      self.leftLabel = leftLabel
      self.rightLabel = rightLabel
      self.context = context
    }
  }
}

extension SessionRequest: Codable {
  private enum CodingKeys: String, CodingKey {
    case version, merge, diff
  }

  /// Decodes a request, refusing one of another protocol version before reading anything else.
  ///
  /// - Throws: ``SessionError/unsupportedVersion(_:)`` for another version, `DecodingError` for
  ///   anything else that is wrong.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try MessageCoding.checkVersion(in: container, forKey: .version)
    switch (container.contains(.merge), container.contains(.diff)) {
    case (true, false): self = .merge(try container.decode(Merge.self, forKey: .merge))
    case (false, true): self = .diff(try container.decode(Diff.self, forKey: .diff))
    default:
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath,
          debugDescription: "A request names exactly one of merge and diff."))
    }
  }

  /// Encodes the request together with the protocol version.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(MessageCoding.version, forKey: .version)
    switch self {
    case .merge(let merge): try container.encode(merge, forKey: .merge)
    case .diff(let diff): try container.encode(diff, forKey: .diff)
    }
  }
}

extension SessionRequest.Merge: Codable {
  private enum CodingKeys: String, CodingKey {
    case base, local, remote, output, context, runByGit
  }

  /// Decodes the files of a merge; a request without `runByGit` comes from a merge that Git does
  /// not wait for.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    base = try container.decodeFileURLIfPresent(forKey: .base)
    local = try container.decodeFileURL(forKey: .local)
    remote = try container.decodeFileURL(forKey: .remote)
    output = try container.decodeFileURL(forKey: .output)
    context = try container.decode(SessionRequest.MergeContext.self, forKey: .context)
    isRunByGit = try container.decodeIfPresent(Bool.self, forKey: .runByGit) ?? false
  }

  /// Encodes the files of a merge as absolute paths; `runByGit` only where Git waits.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeFileURLIfPresent(base, forKey: .base)
    try container.encodeFileURL(local, forKey: .local)
    try container.encodeFileURL(remote, forKey: .remote)
    try container.encodeFileURL(output, forKey: .output)
    try container.encode(context, forKey: .context)
    if isRunByGit {
      try container.encode(true, forKey: .runByGit)
    }
  }
}

extension SessionRequest.Diff: Codable {
  private enum CodingKeys: String, CodingKey {
    case left, right, displayPath, leftLabel, rightLabel, context
  }

  /// Decodes the files of a comparison.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    left = try container.decodeFileURL(forKey: .left)
    right = try container.decodeFileURL(forKey: .right)
    displayPath = try container.decodeIfPresent(String.self, forKey: .displayPath)
    leftLabel = try container.decodeIfPresent(String.self, forKey: .leftLabel)
    rightLabel = try container.decodeIfPresent(String.self, forKey: .rightLabel)
    context = try container.decode(SessionRequest.DiffContext.self, forKey: .context)
  }

  /// Encodes the files of a comparison as absolute paths.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeFileURL(left, forKey: .left)
    try container.encodeFileURL(right, forKey: .right)
    try container.encodeIfPresent(displayPath, forKey: .displayPath)
    try container.encodeIfPresent(leftLabel, forKey: .leftLabel)
    try container.encodeIfPresent(rightLabel, forKey: .rightLabel)
    try container.encode(context, forKey: .context)
  }
}
