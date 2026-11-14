extension SessionRequest {
  /// Where a comparison comes from, which tells the app the comparisons that belong in one window:
  /// those of one run of Git in one repository.
  public struct Origin: Sendable, Hashable, Codable {
    /// The top folder of the working tree, or the folder the tool ran in outside a repository.
    public var repository: String

    /// The process of the run of Git that handed over the file, or `nil` if the tool could not
    /// find it.
    public var run: Run?

    /// Creates an origin.
    public init(repository: String, run: Run?) {
      self.repository = repository
      self.run = run
    }
  }

  /// A process together with the moment it started, which names it even after its ID was given
  /// to another process.
  public struct Run: Sendable, Hashable, Codable {
    /// The ID of the process.
    public var processID: Int32

    /// When the process started, in microseconds since 1970.
    public var startTime: Int64

    /// Creates the description of a process.
    public init(processID: Int32, startTime: Int64) {
      self.processID = processID
      self.startTime = startTime
    }
  }
}
