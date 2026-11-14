import Foundation

extension SessionRequest {
  /// The two folders that `git difftool --dir-diff` fills with the files it compares.
  public struct Folders: Sendable, Hashable {
    /// The folder of the older files, shown on the left.
    public var left: URL

    /// The folder of the newer files, shown on the right.
    public var right: URL

    /// The top folder of the working tree, whose files Git links into a folder, or `nil` outside
    /// a repository.
    public var repository: URL?

    /// Creates the description of a comparison of two folders.
    public init(left: URL, right: URL, repository: URL? = nil) {
      self.left = left
      self.right = right
      self.repository = repository
    }
  }
}

extension SessionRequest.Folders: Codable {
  private enum CodingKeys: String, CodingKey {
    case left, right, repository
  }

  /// Decodes the folders of a comparison.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    left = try container.decodeFileURL(forKey: .left)
    right = try container.decodeFileURL(forKey: .right)
    repository = try container.decodeFileURLIfPresent(forKey: .repository)
  }

  /// Encodes the folders as absolute paths.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeFileURL(left, forKey: .left)
    try container.encodeFileURL(right, forKey: .right)
    try container.encodeFileURLIfPresent(repository, forKey: .repository)
  }
}
