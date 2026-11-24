public import FolderCompare
public import Foundation
public import MergeModel

/// Files that the user put together in the welcome window, each in its role: two to compare, three
/// to merge, or two folders to compare file by file.
public struct FileComparison: Sendable, Hashable {
  /// The file on the left: the older one of a comparison, A of a merge.
  public var left: URL

  /// The common ancestor of a merge, or `nil` for a comparison of two files.
  public var base: URL?

  /// The file on the right: the newer one of a comparison, B of a merge.
  public var right: URL

  /// Whether `left` and `right` are folders, whose files are compared with each other.
  public let comparesFolders: Bool

  /// The sides that hold text pasted from the clipboard, by the location of its copy.
  public let pastedTexts: [URL: PastedText]

  /// Puts files together in their roles; with a base, they are merged.
  public init(left: URL, base: URL? = nil, right: URL) {
    self.init(left: left, base: base, right: right, pastedTexts: [:])
  }

  /// Puts files together in their roles, those of `pastedTexts` as text pasted from the
  /// clipboard.
  init(left: URL, base: URL? = nil, right: URL, pastedTexts: [URL: PastedText]) {
    self.left = left
    self.base = base
    self.right = right
    comparesFolders = false
    self.pastedTexts = pastedTexts.filter { url, _ in [left, base, right].contains(url) }
  }

  /// Puts two files together to compare them, the older one on the left; files of the same age,
  /// or of an age they do not tell, keep their order.
  public init(olderOf first: URL, and second: URL) {
    let modified = { (url: URL) -> Date? in
      do {
        return try url.resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate
      } catch {
        // A file that does not say when it changed keeps its place.
        return nil
      }
    }
    let isSecondOlder =
      if let firstDate = modified(first), let secondDate = modified(second) {
        secondDate < firstDate
      } else {
        false
      }
    self.init(left: isSecondOlder ? second : first, right: isSecondOlder ? first : second)
  }

  /// Puts the two folders of `folders` together, to compare their files.
  public init(folders: FolderPair) {
    let folder = { (url: URL) in
      URL(filePath: url.path(percentEncoded: false), directoryHint: .isDirectory)
    }
    left = folder(folders.left)
    base = nil
    right = folder(folders.right)
    comparesFolders = true
    pastedTexts = [:]
  }

  /// The folders compared, if the comparison is one of two folders.
  public var folders: FolderPair? {
    comparesFolders ? FolderPair(left: left, right: right) : nil
  }

  /// Whether the files are merged or compared.
  public var kind: Session.Kind { base == nil ? .diff : .merge }

  /// The files from left to right, as the panes show them.
  public var files: [URL] { [left, base, right].compactMap(\.self) }

  /// The file at `url`, one of ``files``, as a session reads it: named Clipboard if it holds
  /// pasted text, with the time it was pasted if another side holds pasted text as well, and
  /// else by its file name.
  public func sessionFile(at url: URL) -> SessionFile {
    let label =
      pastedTexts[url]?.name(withTime: pastedTexts.count > 1) ?? url.lastPathComponent
    return SessionFile(url: url, label: label)
  }

  /// The names of the files from left to right, as a line of a list or a menu shows them.
  public var title: String {
    let names = files.map(\.lastPathComponent)
    return names.count == 3
      ? String(
        localized: "\(names[0]) ↔ \(names[1]) ↔ \(names[2])", bundle: .module,
        comment: "A recent merge: the names of A, the base and B.")
      : String(
        localized: "\(names[0]) ↔ \(names[1])", bundle: .module,
        comment: "The names of the left and the right file of a comparison, in a title or list.")
  }

  /// The innermost folder that holds every file, with the home folder as a tilde.
  public var folder: String {
    let folders = files.map { $0.deletingLastPathComponent().standardizedFileURL.pathComponents }
    var shared = folders[0]
    for components in folders.dropFirst() {
      shared = Array(zip(shared, components).prefix { $0 == $1 }.map(\.0))
    }
    let path = NSString.path(withComponents: shared.isEmpty ? ["/"] : shared)
    return (path as NSString).abbreviatingWithTildeInPath
  }

  /// What VoiceOver says for the comparison in a list.
  var accessibilityTitle: String {
    let names = files.map(\.lastPathComponent)
    if comparesFolders {
      return String(
        localized: "Compare the folder \(names[0]) with \(names[1])", bundle: .module,
        comment: "VoiceOver: a recent comparison of two folders, with their names.")
    }
    return names.count == 3
      ? String(
        localized: "Merge \(names[0]) and \(names[2]) with the base \(names[1])", bundle: .module,
        comment: "VoiceOver: a recent merge, with the names of A, B and the base.")
      : String(
        localized: "Compare \(names[0]) with \(names[1])", bundle: .module,
        comment: "VoiceOver: a recent comparison, with the names of the left and the right file.")
  }
}
