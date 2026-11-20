public import Foundation

/// Two folders compared with each other, the older on the left.
public struct FolderPair: Sendable, Hashable {
  /// The folder shown on the left.
  public var left: URL

  /// The folder shown on the right.
  public var right: URL

  /// Pairs `left` with `right`.
  public init(left: URL, right: URL) {
    self.left = left
    self.right = right
  }

  /// The names of the folders, as a subtitle or a list shows them.
  public var title: String {
    let names = distinctNames
    return String(
      localized: "\(names.left) ↔ \(names.right)", bundle: .module,
      comment: "The names of the left and the right file of a comparison, in a title or list.")
  }

  /// The names that tell the folders apart: their own names, or where these are the same, the
  /// shortest ends of their paths that differ, such as “app/src” and “lib/src”.
  public var distinctNames: (left: String, right: String) {
    let leftParts = left.standardizedFileURL.pathComponents
    let rightParts = right.standardizedFileURL.pathComponents
    for count in 1...max(leftParts.count, rightParts.count) {
      let leftEnd = leftParts.suffix(count)
      let rightEnd = rightParts.suffix(count)
      if leftEnd != rightEnd || count >= min(leftParts.count, rightParts.count) {
        return (Self.path(of: leftEnd), Self.path(of: rightEnd))
      }
    }
    return (left.lastPathComponent, right.lastPathComponent)
  }

  private static func path(of components: ArraySlice<String>) -> String {
    NSString.path(withComponents: Array(components))
  }
}
