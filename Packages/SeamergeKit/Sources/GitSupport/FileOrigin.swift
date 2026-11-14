import Foundation

/// Where a file that Git or Tower hands to the tool comes from.
public enum FileOrigin: Sendable, Hashable {
  /// No file: `/dev/null`, which stands for the side of a file that is new or deleted.
  case missing

  /// A copy in a temporary folder, such as one of the files `git difftool` writes for a commit.
  case temporaryCopy

  /// Any other file, such as the file in the working tree.
  case ordinary

  /// The origin of the file at `url`; `temporaryDirectory` is the temporary folder of the user.
  public init(url: URL, temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
    let path = Self.canonicalPath(of: url)
    if path == "/dev/null" {
      self = .missing
      return
    }
    // A path that does not exist keeps its symbolic links, such as /tmp for /private/tmp.
    let paths = [path, url.standardizedFileURL.path]
    let folders = [
      Self.canonicalPath(of: temporaryDirectory), temporaryDirectory.standardizedFileURL.path,
      "/private/tmp", "/tmp",
    ].map { $0.hasSuffix("/") ? $0 : $0 + "/" }
    let isTemporary = paths.contains { path in folders.contains { path.hasPrefix($0) } }
    self = isTemporary ? .temporaryCopy : .ordinary
  }

  static func canonicalPath(of url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
  }
}
