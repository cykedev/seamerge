import Foundation
import GitSupport
import MergeModel
import os

/// Compares two folders entry by entry: pairs the entries of both by their paths, and tells what
/// happened to each pair, by the size where that suffices and by the bytes where it must.
///
/// Paths pair in their composed Unicode form, so that a name with a decomposed umlaut finds the
/// same name composed; case counts as the file system of the left folder counts it. A link is
/// compared by its target as text and never followed, so that a link to a folder above it makes
/// no loop.
///
/// Folders that `git difftool --dir-diff` filled hold links to the files of the working tree,
/// unless Git is told to copy them. With the working tree given, such a link to a file stands
/// for that file, the working copy, which the user can open and edit; a link to a file of the
/// working tree that is a link itself is compared by that file's target.
struct FolderComparer: Sendable {
  /// The folders, as the user chose them.
  let folders: FolderPair

  /// Whether the file system of the left folder tells names apart by case.
  let isCaseSensitive: Bool

  /// The top of the working tree whose files the links of Git lead to, as a canonical path that
  /// ends with a slash, or `nil` outside a comparison of Git.
  let workingTree: String?

  private let left: FolderListing
  private let right: FolderListing
  private let linkFolder: URL

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// The bytes read from each side at a time while comparing the contents of two files.
  private static let chunkSize = 64 * 1024

  /// Compares the folders of `folders`; the targets of links go as text into `linkFolder`, which
  /// the caller removes once the comparison is no longer shown.
  ///
  /// Links into `workingTree`, the working tree of a comparison of `git difftool --dir-diff`,
  /// stand for its files.
  init(folders: FolderPair, linkFolder: URL, workingTree: URL? = nil) {
    self.folders = folders
    self.linkFolder = linkFolder
    self.workingTree = workingTree.map { tree in
      let path = Self.canonicalPath(of: tree)
      return path.hasSuffix("/") ? path : path + "/"
    }
    // The real path, as the file system reports changes; resolving the links of the URL would
    // drop the /private of /var and /tmp.
    let root = { (url: URL) in
      let path = url.path(percentEncoded: false)
      return URL(
        filePath: realpath(path, nil).map { real in
          defer { free(real) }
          return String(cString: real)
        } ?? path,
        directoryHint: .isDirectory)
    }
    left = FolderListing(root: root(folders.left))
    right = FolderListing(root: root(folders.right))
    do {
      isCaseSensitive =
        try left.root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        .volumeSupportsCaseSensitiveNames ?? false
    } catch {
      Self.logger.error("Cannot tell whether names differ by case: \(error, privacy: .public)")
      isCaseSensitive = false
    }
  }

  /// The tops of the folders from the root of the file system, links in their paths resolved,
  /// as the file system reports changes in them.
  var roots: (left: String, right: String) {
    (left.absolutePath(of: ""), right.absolutePath(of: ""))
  }

  /// The form of `path` in which paths of both folders pair.
  func key(of path: String) -> String {
    let composed = path.precomposedStringWithCanonicalMapping
    return isCaseSensitive ? composed : composed.folding(options: .caseInsensitive, locale: nil)
  }

  /// The entries of both folders at `path` and below, paired, in the order of the list.
  ///
  /// `path` may be spelled as either folder spells it. Where a side has a folder it cannot read,
  /// the pair of that folder stands for everything below it, so that its files on the other
  /// side do not show as new or deleted.
  func pairs(at path: String) -> [Pair] {
    let key = { (path: String) in self.key(of: path) }
    let leftItems = left.spelling(of: path, key: key).map(left.items(at:)) ?? []
    let rightItems = right.spelling(of: path, key: key).map(right.items(at:)) ?? []
    var pairs: [String: Pair] = [:]
    for item in leftItems {
      pairs[self.key(of: item.path), default: Pair(path: item.path)].left = resolved(item, in: left)
    }
    for item in rightItems {
      pairs[self.key(of: item.path), default: Pair(path: item.path)].right = resolved(
        item, in: right)
    }
    let unreadable = Set(pairs.filter { $0.value.isUnreadable }.keys)
    if !unreadable.isEmpty {
      pairs = pairs.filter { key, _ in !Self.liesBelow(key, anyOf: unreadable) }
    }
    return pairs.values.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
  }

  /// `item`, or, for a link of Git into the working tree, the file of the working tree it leads
  /// to.
  ///
  /// A link to a link there is compared by the target of that link; a hanging link stays as it
  /// is.
  private func resolved(_ item: FolderItem, in listing: FolderListing) -> FolderItem {
    guard let workingTree, case .link(let target) = item.kind else { return item }
    let link = URL(filePath: listing.absolutePath(of: item.path))
    let destination = URL(filePath: target, relativeTo: link.deletingLastPathComponent())
      .standardizedFileURL
    guard Self.canonicalPath(of: destination).hasPrefix(workingTree) else { return item }
    var info = stat()
    guard lstat(destination.path(percentEncoded: false), &info) == 0 else { return item }
    switch info.st_mode & S_IFMT {
    case S_IFREG:
      return FolderItem(
        path: item.path,
        kind: .workingCopy(
          path: destination.path(percentEncoded: false), size: Int64(info.st_size)))
    case S_IFLNK:
      do {
        let ownTarget = try FileManager.default.destinationOfSymbolicLink(
          atPath: destination.path(percentEncoded: false))
        return FolderItem(path: item.path, kind: .link(target: ownTarget))
      } catch {
        return FolderItem(
          path: item.path, kind: .unreadable(reason: FolderListing.reason(for: error)))
      }
    default:
      return item
    }
  }

  /// The path of `url` with every link in it resolved, as links of Git name the working tree.
  private static func canonicalPath(of url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
  }

  /// Whether the path of `key` lies below one of `keys`, looking only at the folders above it.
  private static func liesBelow(_ key: String, anyOf keys: Set<String>) -> Bool {
    var prefix = key[...]
    while let slash = prefix.lastIndex(of: "/") {
      prefix = prefix[..<slash]
      if keys.contains(String(prefix)) {
        return true
      }
    }
    return false
  }

  /// What happened to `pair` as far as it shows without reading the files, or `nil` if only
  /// their bytes tell.
  func change(withoutReading pair: Pair) -> CollectedFile.Change? {
    switch (pair.left?.kind, pair.right?.kind) {
    case (.unreadable(let reason), _), (_, .unreadable(let reason)):
      return .unreadable(reason: reason)
    case (nil, _):
      return .added
    case (_, nil):
      return .deleted
    case (.link(let leftTarget), .link(let rightTarget)):
      return leftTarget == rightTarget ? .identical : .modified
    case (.file(let leftSize), .file(let rightSize)),
      (.file(let leftSize), .workingCopy(_, let rightSize)),
      (.workingCopy(_, let leftSize), .file(let rightSize)),
      (.workingCopy(_, let leftSize), .workingCopy(_, let rightSize)):
      return leftSize == rightSize ? nil : .modified
    case (.file, .link), (.link, .file), (.workingCopy, .link), (.link, .workingCopy):
      return .modified
    }
  }

  /// What happened to `pair`: from the size or the targets where they tell, else from the bytes,
  /// read only up to the first that differs.
  func change(of pair: Pair) -> CollectedFile.Change {
    if let change = change(withoutReading: pair) {
      return change
    }
    guard let leftItem = pair.left, let rightItem = pair.right else { return .modified }
    let leftURL = Self.url(of: leftItem, in: left)
    let rightURL = Self.url(of: rightItem, in: right)
    do {
      let leftHandle = try FileHandle(forReadingFrom: leftURL)
      defer { close(leftHandle) }
      let rightHandle = try FileHandle(forReadingFrom: rightURL)
      defer { close(rightHandle) }
      while true {
        let (leftChunk, rightChunk) = try autoreleasepool {
          (
            try leftHandle.read(upToCount: Self.chunkSize) ?? Data(),
            try rightHandle.read(upToCount: Self.chunkSize) ?? Data()
          )
        }
        guard leftChunk == rightChunk else { return .modified }
        if leftChunk.isEmpty {
          return .identical
        }
      }
    } catch {
      return .unreadable(reason: FolderListing.reason(for: error))
    }
  }

  /// The file whose bytes stand for `item` of `listing`: the file of the working tree for a link
  /// of Git, else the entry itself.
  private static func url(of item: FolderItem, in listing: FolderListing) -> URL {
    if case .workingCopy(let path, _) = item.kind {
      return URL(filePath: path)
    }
    return URL(filePath: listing.absolutePath(of: item.path))
  }

  /// The file of the list for `pair`, to which `change` happened.
  ///
  /// The sides are the files themselves, below the tops of their folders, or the working copy
  /// that a link of Git leads to; any other link is a file in the folder of links that holds its
  /// target.
  func file(for pair: Pair, change: CollectedFile.Change) -> CollectedFile {
    CollectedFile(
      old: side(pair.left, in: left), new: side(pair.right, in: right),
      difftool: DifftoolContext(
        path: pair.path, leftRole: pair.left?.isWorkingCopy == true ? .workingCopy : .before,
        rightRole: pair.right?.isWorkingCopy == true ? .workingCopy : .after),
      change: change)
  }

  private func side(_ item: FolderItem?, in listing: FolderListing) -> CollectedFile.Side {
    guard let item else { return .missing }
    if case .workingCopy(let path, _) = item.kind {
      return .file(SessionFile(url: URL(filePath: path), label: ""))
    }
    guard case .link(let target) = item.kind else {
      return .entry(folder: listing.root, path: item.path)
    }
    let text = linkFolder.appending(path: UUID().uuidString).appending(
      path: (item.path as NSString).lastPathComponent)
    do {
      try FileManager.default.createDirectory(
        at: text.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(target.utf8).write(to: text)
    } catch {
      Self.logger.error(
        "Cannot write the target of the link \(item.path, privacy: .public): \(error, privacy: .public)"
      )
      return .entry(folder: listing.root, path: item.path)
    }
    return .file(SessionFile(url: text, label: ""))
  }

  private func close(_ handle: FileHandle) {
    do {
      try handle.close()
    } catch {
      Self.logger.error("Cannot close a compared file: \(error, privacy: .public)")
    }
  }

  /// The entries of both folders at one path; at least one of them is there.
  struct Pair: Sendable, Hashable {
    /// The path, as the left folder spells it if it has the entry.
    var path: String

    /// The entry of the left folder, if it has one.
    var left: FolderItem?

    /// The entry of the right folder, if it has one.
    var right: FolderItem? {
      didSet {
        if left == nil, let right {
          path = right.path
        }
      }
    }

    init(path: String) {
      self.path = path
    }

    /// Whether a side cannot be read.
    var isUnreadable: Bool {
      [left, right].contains { item in
        if case .unreadable = item?.kind { true } else { false }
      }
    }
  }
}
