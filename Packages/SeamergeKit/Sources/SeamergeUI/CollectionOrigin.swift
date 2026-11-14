import GitSupport

/// Where the comparisons of a window that collects them come from: one run of Git in one
/// repository.
public struct CollectionOrigin: Sendable, Hashable {
  /// The top folder of the working tree, or the folder the tool ran in outside a repository.
  public var repository: String

  /// The process of the run of Git, or `nil` if the tool could not find it.
  public var run: ProcessRun?

  /// Creates an origin.
  public init(repository: String, run: ProcessRun?) {
    self.repository = repository
    self.run = run
  }
}
