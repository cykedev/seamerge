import Foundation
import GitSupport
import os

/// The files of two folders that `git difftool --dir-diff` filled, paired by their paths.
///
/// Git puts into the folders only the files a comparison touches, and links a file of the working
/// tree instead of copying it, unless it is told not to. Such a link is followed, so that the side
/// is the working copy, which the user can open. Any other link is a file of the repository that
/// is a link itself; it is compared by its target, as Git compares it, and never followed.
public enum FolderComparison {
  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// The files that differ between `left` and `right`, paired by path.
  ///
  /// A file only on the right is new, one only on the left deleted; a file renamed between the
  /// folders is one of each.
  ///
  /// - Parameters:
  ///   - left: The folder of the older files.
  ///   - right: The folder of the newer files.
  ///   - workingTree: The top folder of the working tree, whose files are working copies.
  ///   - linkFolder: A folder for the targets of links, written as text so that the window can
  ///     show them; the caller removes it with the window.
  @concurrent
  public static func files(
    left: URL, right: URL, workingTree: URL?, linkFolder: URL
  ) async -> [CollectedFile] {
    let (leftFiles, rightFiles) = (relativePaths(in: left), relativePaths(in: right))
    let tree = workingTree.map { canonicalPath(of: $0) + "/" }
    let missing = URL(filePath: "/dev/null")
    var files: [CollectedFile] = []
    for path in leftFiles.union(rightFiles) {
      let old =
        leftFiles.contains(path)
        ? side(left.appending(path: path), workingTree: tree, linkFolder: linkFolder) : nil
      let new =
        rightFiles.contains(path)
        ? side(right.appending(path: path), workingTree: tree, linkFolder: linkFolder) : nil
      if let old, let new,
        FileManager.default.contentsEqual(atPath: old.url.path, andPath: new.url.path)
      {
        continue
      }
      files.append(
        CollectedFile(
          old: SessionFile(url: old?.url ?? missing, label: path),
          new: SessionFile(url: new?.url ?? missing, label: path),
          difftool: DifftoolContext(
            path: path, leftRole: old?.isWorkingCopy == true ? .workingCopy : .before,
            rightRole: new?.isWorkingCopy == true ? .workingCopy : .after)))
    }
    return files.sorted { $0.precedes($1) }
  }

  /// What the window shows for the entry at `url`: the entry itself; for a link to a file of the
  /// working tree that file; for any other link, a hanging one too, and for a link to a link of
  /// the working tree, a file in `linkFolder` that holds the target as text.
  private static func side(
    _ url: URL, workingTree: String?, linkFolder: URL
  ) -> (url: URL, isWorkingCopy: Bool) {
    guard var target = linkTarget(of: url) else { return (url, false) }
    let destination = URL(filePath: target, relativeTo: url.deletingLastPathComponent())
      .standardizedFileURL
    if let workingTree, canonicalPath(of: destination).hasPrefix(workingTree) {
      if isRegularFile(destination) {
        return (destination, true)
      }
      // Git linked a file of the working tree that is a link itself.
      if let ownTarget = linkTarget(of: destination) {
        target = ownTarget
      }
    }
    let text = linkFolder.appending(path: UUID().uuidString).appending(
      path: url.lastPathComponent)
    do {
      try FileManager.default.createDirectory(
        at: text.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(target.utf8).write(to: text)
    } catch {
      logger.error("Cannot write the target of the link \(url.path): \(error, privacy: .public)")
      return (url, false)
    }
    return (text, false)
  }

  /// The target of the link at `url`, or `nil` if it is no link.
  private static func linkTarget(of url: URL) -> String? {
    let path = url.path(percentEncoded: false)
    guard entryType(at: path) == .typeSymbolicLink else { return nil }
    do {
      return try FileManager.default.destinationOfSymbolicLink(atPath: path)
    } catch {
      logger.error("Cannot read the link \(path): \(error, privacy: .public)")
      return nil
    }
  }

  /// Whether `url` is a file and no link or folder, without following a link.
  private static func isRegularFile(_ url: URL) -> Bool {
    entryType(at: url.path(percentEncoded: false)) == .typeRegular
  }

  /// The type of the entry at `path`, without following a link, or `nil` if there is none.
  private static func entryType(at path: String) -> FileAttributeType? {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: path)
      return (attributes[.type] as? String).map(FileAttributeType.init(rawValue:))
    } catch {
      // Nothing is at the path, or it cannot be read; either way it is no entry to compare.
      return nil
    }
  }

  /// The paths of the files in `folder`, relative to it, links among them, hanging ones too.
  private static func relativePaths(in folder: URL) -> Set<String> {
    let root = folder.path(percentEncoded: false)
    guard let enumerator = FileManager.default.enumerator(atPath: root) else {
      logger.error("Cannot list the files of \(root)")
      return []
    }
    var paths: Set<String> = []
    for case let path as String in enumerator
    where entryType(at: folder.appending(path: path).path(percentEncoded: false))
      != .typeDirectory
    {
      paths.insert(path)
    }
    return paths
  }

  private static func canonicalPath(of url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
  }
}
