import Darwin
import Foundation

/// An entry of a folder as a comparison of folders sees it: a file, a link, or something it
/// cannot read.
struct FolderItem: Sendable, Hashable {
  /// What the entry is.
  enum Kind: Sendable, Hashable {
    /// A file of `size` bytes.
    case file(size: Int64)

    /// A symbolic link, which is compared by its target and never followed.
    case link(target: String)

    /// A link that `git difftool --dir-diff` put in place of the file at `path` in the working
    /// tree, of `size` bytes; the file is compared and shown as the working copy.
    case workingCopy(path: String, size: Int64)

    /// A file or folder that cannot be read, for the reason given.
    case unreadable(reason: String)
  }

  /// The path of the entry relative to the top of its folder, in the spelling of the file
  /// system.
  let path: String

  /// What the entry is.
  let kind: Kind

  /// Whether the entry stands for a file of the working tree.
  var isWorkingCopy: Bool {
    if case .workingCopy = kind { true } else { false }
  }
}

/// Lists the entries of a folder for a comparison of folders, without following a link.
///
/// The listing enters every folder, packages such as `.app` too, and leaves out only `.git` and
/// `.DS_Store`. A folder it cannot open is one entry that says why; so is anything that is
/// neither file, folder nor link, such as a socket, which reading would block on.
struct FolderListing: Sendable {
  /// The top of the folder.
  let root: URL

  private let rootPath: String

  /// The names of the entries that a listing leaves out, with whatever lies below them.
  static let skippedNames: Set<String> = [".git", ".DS_Store"]

  /// Lists the folder at `root`.
  init(root: URL) {
    self.root = root
    let path = root.path(percentEncoded: false)
    rootPath = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
  }

  /// The entries at `path`, relative to the top, and below it: the entry itself if it is a file
  /// or a link, the entries of the folder and its subfolders if it is a folder, none if nothing
  /// is there.
  func items(at path: String) -> [FolderItem] {
    switch status(of: path) {
    case .missing:
      return []
    case .failed(let reason):
      return [FolderItem(path: path, kind: .unreadable(reason: reason))]
    case .entry(let status):
      guard status.isFolder else { return item(at: path, status: status).map { [$0] } ?? [] }
    }
    var items: [FolderItem] = []
    var folders = [path]
    while let folder = folders.popLast() {
      let names: [String]
      do {
        names = try FileManager.default.contentsOfDirectory(atPath: absolutePath(of: folder))
      } catch {
        items.append(FolderItem(path: folder, kind: .unreadable(reason: Self.reason(for: error))))
        continue
      }
      for name in names where !Self.skippedNames.contains(name) {
        let child = folder.isEmpty ? name : folder + "/" + name
        switch status(of: child) {
        case .missing:
          // Removed since the folder was read.
          continue
        case .failed(let reason):
          items.append(FolderItem(path: child, kind: .unreadable(reason: reason)))
        case .entry(let status) where status.isFolder:
          folders.append(child)
        case .entry(let status):
          if let item = item(at: child, status: status) {
            items.append(item)
          }
        }
      }
    }
    return items
  }

  /// The spelling in this folder of `path`, a path that may be spelled otherwise in the other
  /// folder, or `nil` if no entry there has it.
  ///
  /// Each name along the path is found among the entries of its folder by `key`, which pairs
  /// names that differ only in their Unicode form, and in case where the file system ignores it.
  func spelling(of path: String, key: (String) -> String) -> String? {
    guard !path.isEmpty else { return path }
    if case .entry = status(of: path) {
      return path
    }
    var found = ""
    for name in path.split(separator: "/").map(String.init) {
      let names: [String]
      do {
        names = try FileManager.default.contentsOfDirectory(atPath: absolutePath(of: found))
      } catch {
        // The folder cannot be read, or is no folder: nothing below it is there to pair with.
        return nil
      }
      guard let match = names.first(where: { key($0) == key(name) }) else { return nil }
      found = found.isEmpty ? match : found + "/" + match
    }
    return found
  }

  /// The path of `path`, relative to the top, from the root of the file system.
  func absolutePath(of path: String) -> String {
    path.isEmpty ? rootPath : rootPath + "/" + path
  }

  /// What is at `path`, without following a link.
  private func status(of path: String) -> EntryStatus {
    var info = stat()
    guard lstat(absolutePath(of: path), &info) == 0 else {
      let code = errno
      return code == ENOENT || code == ENOTDIR ? .missing : .failed(Self.reason(forCode: code))
    }
    return .entry(FileStatus(mode: info.st_mode & S_IFMT, size: Int64(info.st_size)))
  }

  /// The entry at `path`, which is no folder.
  private func item(at path: String, status: FileStatus) -> FolderItem? {
    switch status.mode {
    case S_IFREG:
      return FolderItem(path: path, kind: .file(size: status.size))
    case S_IFLNK:
      do {
        let target = try FileManager.default.destinationOfSymbolicLink(
          atPath: absolutePath(of: path))
        return FolderItem(path: path, kind: .link(target: target))
      } catch {
        return FolderItem(path: path, kind: .unreadable(reason: Self.reason(for: error)))
      }
    default:
      return FolderItem(path: path, kind: .unreadable(reason: Self.specialFileReason))
    }
  }

  /// Why an entry cannot be read, in the words of the system.
  static func reason(for error: any Error) -> String {
    let error = error as NSError
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError,
      underlying.domain == NSPOSIXErrorDomain
    {
      return reason(forCode: Int32(underlying.code))
    }
    return error.localizedFailureReason ?? error.localizedDescription
  }

  /// Why an entry cannot be read, for the error number `code` of the system.
  static func reason(forCode code: Int32) -> String {
    switch code {
    case EACCES, EPERM:
      String(
        localized: "You don’t have permission to read it.", bundle: .module,
        comment: "Why a file or folder of a comparison of folders cannot be read.")
    default:
      String(cString: strerror(code))
    }
  }

  private static var specialFileReason: String {
    String(
      localized: "It is neither a file, a folder nor a link.", bundle: .module,
      comment: "Why an entry of a comparison of folders, such as a socket, is not compared.")
  }

  private enum EntryStatus {
    case missing
    case failed(String)
    case entry(FileStatus)
  }

  private struct FileStatus {
    let mode: mode_t
    let size: Int64

    var isFolder: Bool { mode == S_IFDIR }
  }
}
