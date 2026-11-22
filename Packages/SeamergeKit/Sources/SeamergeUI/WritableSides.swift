import FolderCompare
import Foundation
import GitSupport
import MergeModel
import os

/// The files of a comparison that copying a change may write to, decided once as the window
/// opens its files.
///
/// A comparison that Git or Tower started offers only the working copy: the other sides are
/// copies of a commit or of the index in a temporary folder, which the next run replaces, so
/// that what is copied there would look like work and be lost. Any other comparison compares
/// files the user chose, and each of them may be written, wherever it lies; only in a comparison
/// of two folders does a file have to lie in its folder, since a symbolic link there is shown by
/// its target, as a text the app writes elsewhere, which no one would read. Either way, a file
/// is written only if it is an ordinary file once symbolic links are resolved, the user may
/// write it, and its volume is not read-only; the missing side of a new or deleted file,
/// `/dev/null`, never is.
///
/// The value names the files by their role, so it moves with them when Swap Sides puts them the
/// other way round.
struct WritableSides: Sendable, Hashable {
  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// The roles of the files that may be written.
  private let roles: Set<Role>

  /// Decides which of `old`, file A, and `new`, file B, may be written, for a comparison that
  /// `context` describes.
  ///
  /// The comparison comes from Git or Tower if `context` tells what Git says about it.
  init(old: SessionFile, new: SessionFile, context: SessionContext) {
    // A comparison of folders that the user chose describes its files as Git would, but names
    // its sides after the folders.
    let git = context.folders == nil ? context.difftool : nil
    let sides: [(role: Role, file: SessionFile, gitRole: DiffSideRole?, folder: URL?)] = [
      (.a, old, git?.leftRole, context.folders?.left),
      (.b, new, git?.rightRole, context.folders?.right),
    ]
    roles = Set(
      sides.filter { side in
        (git == nil || side.gitRole == .workingCopy)
          && side.folder.map { Self.folder($0, holds: side.file.url) } ?? true
          && Self.canWrite(side.file.url)
      }.map(\.role))
  }

  /// Whether the file at `url` lies in `folder` or a folder within it, links in both paths
  /// resolved.
  private static func folder(_ folder: URL, holds url: URL) -> Bool {
    let top = folder.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    return path.hasPrefix(top.hasSuffix("/") ? top : top + "/")
  }

  /// Whether the file of `role` may be written.
  func contains(_ role: Role) -> Bool {
    roles.contains(role)
  }

  /// Whether Copy to Right may write: the file on the right of `arrangement` may be written.
  ///
  /// The right is the side `arrangement` shows there now, after any Swap Sides.
  func allowsCopyToRight(in arrangement: PaneArrangement) -> Bool {
    contains(arrangement.trailingRole)
  }

  /// Whether Copy to Left may write: the file on the left of `arrangement` may be written.
  ///
  /// The left is the side `arrangement` shows there now, after any Swap Sides.
  func allowsCopyToLeft(in arrangement: PaneArrangement) -> Bool {
    contains(arrangement.leadingRole)
  }

  /// Whether no file may be written.
  var isEmpty: Bool {
    roles.isEmpty
  }

  /// Whether the file at `url`, once symbolic links are resolved, is an ordinary file that the
  /// user may write on a volume that is not read-only.
  private static func canWrite(_ url: URL) -> Bool {
    let file = url.resolvingSymlinksInPath()
    let values: URLResourceValues
    do {
      values = try file.resourceValues(forKeys: [.isRegularFileKey, .volumeIsReadOnlyKey])
    } catch {
      logger.info(
        "Not writing \(file.path, privacy: .public), which cannot be read: \(error, privacy: .public)"
      )
      return false
    }
    return values.isRegularFile == true && values.volumeIsReadOnly != true
      && FileManager.default.isWritableFile(atPath: file.path(percentEncoded: false))
  }
}
