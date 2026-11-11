extension SessionRequest {
  /// What Git says about a comparison through `git difftool`.
  public struct DiffContext: Sendable, Hashable, Codable {
    /// What the left side is.
    public var leftRole: DiffSideRole

    /// What the right side is.
    public var rightRole: DiffSideRole

    /// Which file of the run this is, if Git tells.
    public var filePosition: FilePosition?

    /// Creates a context; without arguments, the older file left and the newer one right.
    public init(
      leftRole: DiffSideRole = .before,
      rightRole: DiffSideRole = .after,
      filePosition: FilePosition? = nil
    ) {
      self.leftRole = leftRole
      self.rightRole = rightRole
      self.filePosition = filePosition
    }
  }

  /// What one side of a comparison is.
  public enum DiffSideRole: String, Sendable, Hashable, Codable {
    /// The file before the change.
    case before

    /// The file after the change.
    case after

    /// The file in the working tree, which the user can edit.
    case workingCopy
  }

  /// The position of a file among the files of one `git difftool` run.
  public struct FilePosition: Sendable, Hashable, Codable {
    /// The number of the file, counted from 1.
    public var number: Int

    /// How many files the run compares.
    public var count: Int

    /// Creates a position.
    public init(number: Int, count: Int) {
      self.number = number
      self.count = count
    }
  }
}
