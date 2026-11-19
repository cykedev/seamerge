public import Foundation

extension Git {
  /// The top folder of the working tree that contains `directory`, or `nil` outside a working
  /// tree or if Git cannot tell.
  public func topLevel(of directory: URL) -> URL? {
    Repository(git: self, workingDirectory: directory)?.topLevel
  }
}
