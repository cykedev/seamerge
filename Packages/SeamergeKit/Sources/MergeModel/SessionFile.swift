public import Foundation

/// A file to read for a session, with the label its header shows where nothing else names its
/// side.
public struct SessionFile: Sendable, Hashable {
  /// Where the file is.
  public var url: URL

  /// The name of the side when nothing else names it.
  public var label: String

  /// Names the file at `url`, which shows as `label` where nothing else names its side.
  public init(url: URL, label: String) {
    self.url = url
    self.label = label
  }
}
