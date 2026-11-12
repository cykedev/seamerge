import Foundation
import MergeModel

/// Files that the user put together in the window Compare Files, each in its role: two to compare,
/// or three to merge.
public struct FileComparison: Sendable, Hashable {
  /// The file on the left: the older one of a comparison, A of a merge.
  public var left: URL

  /// The common ancestor of a merge, or `nil` for a comparison of two files.
  public var base: URL?

  /// The file on the right: the newer one of a comparison, B of a merge.
  public var right: URL

  /// Puts files together in their roles; with a base, they are merged.
  public init(left: URL, base: URL? = nil, right: URL) {
    self.left = left
    self.base = base
    self.right = right
  }

  /// Whether the files are merged or compared.
  public var kind: Session.Kind { base == nil ? .diff : .merge }

  /// The files from left to right, as the panes show them.
  public var files: [URL] { [left, base, right].compactMap(\.self) }

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
    return names.count == 3
      ? String(
        localized: "Merge \(names[0]) and \(names[2]) with the base \(names[1])", bundle: .module,
        comment: "VoiceOver: a recent merge, with the names of A, B and the base.")
      : String(
        localized: "Compare \(names[0]) with \(names[1])", bundle: .module,
        comment: "VoiceOver: a recent comparison, with the names of the left and the right file.")
  }
}
