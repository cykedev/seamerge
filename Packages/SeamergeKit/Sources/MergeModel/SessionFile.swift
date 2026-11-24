public import Foundation

/// A file to read for a session, with the label its header shows where nothing else names its
/// side.
public struct SessionFile: Sendable, Hashable {
  /// Where the file is.
  public var url: URL

  /// The name of the side when nothing else names it.
  public var label: String

  /// The side of a file of a patch whose text the file holds, which the file read from it then
  /// holds too; `nil` for any other file.
  public var patchSide: PatchFile.Side?

  /// Names the file at `url`, which shows as `label` where nothing else names its side, and
  /// which holds `patchSide` if it is the side of a file of a patch.
  public init(url: URL, label: String, patchSide: PatchFile.Side? = nil) {
    self.url = url
    self.label = label
    self.patchSide = patchSide
  }
}
