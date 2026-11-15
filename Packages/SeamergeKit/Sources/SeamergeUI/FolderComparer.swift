import Foundation
import GitSupport
import os

/// Compares two folders entry by entry: pairs the entries of both by their paths, and tells what
/// happened to each pair, by the size where that suffices and by the bytes where it must.
///
/// Paths pair in their composed Unicode form, so that a name with a decomposed umlaut finds the
/// same name composed; case counts as the file system of the left folder counts it. A link is
/// compared by its target as text and never followed, so that a link to a folder above it makes
/// no loop.
struct FolderComparer: Sendable {
  /// The folders, as the user chose them.
  let folders: FolderPair

  /// Whether the file system of the left folder tells names apart by case.
  let isCaseSensitive: Bool

  private let left: FolderListing
  private let right: FolderListing
  private let linkFolder: URL

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// The bytes read from each side at a time while comparing the contents of two files.
  private static let chunkSize = 64 * 1024

  /// Compares the folders of `folders`; the targets of links go as text into `linkFolder`, which
  /// the caller removes once the comparison is no longer shown.
  init(folders: FolderPair, linkFolder: URL) {
    self.folders = folders
    self.linkFolder = linkFolder
    // The real path, which resolving the links of the URL is not: it drops the /private of /var
    // and /tmp.
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
      pairs[self.key(of: item.path), default: Pair(path: item.path)].left = item
    }
    for item in rightItems {
      pairs[self.key(of: item.path), default: Pair(path: item.path)].right = item
    }
    let unreadable = Set(pairs.filter { $0.value.isUnreadable }.keys)
    if !unreadable.isEmpty {
      pairs = pairs.filter { key, _ in !Self.liesBelow(key, anyOf: unreadable) }
    }
    return pairs.values.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
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
    case (.file(let leftSize), .file(let rightSize)):
      return leftSize == rightSize ? nil : .modified
    case (.file, .link), (.link, .file):
      return .modified
    }
  }

  /// What happened to `pair`: from the size or the targets where they tell, else from the bytes,
  /// read only up to the first that differs.
  func change(of pair: Pair) -> CollectedFile.Change {
    if let change = change(withoutReading: pair) {
      return change
    }
    guard let leftPath = pair.left?.path, let rightPath = pair.right?.path else { return .modified }
    let leftURL = URL(filePath: left.absolutePath(of: leftPath))
    let rightURL = URL(filePath: right.absolutePath(of: rightPath))
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

  /// The file of the list for `pair`, to which `change` happened.
  ///
  /// The sides are the files themselves, below the tops of their folders; a link is a file in the
  /// folder of links that holds its target.
  func file(for pair: Pair, change: CollectedFile.Change) -> CollectedFile {
    CollectedFile(
      old: side(pair.left, in: left), new: side(pair.right, in: right),
      difftool: DifftoolContext(path: pair.path), change: change)
  }

  private func side(_ item: FolderItem?, in listing: FolderListing) -> CollectedFile.Side {
    guard let item else { return .missing }
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
