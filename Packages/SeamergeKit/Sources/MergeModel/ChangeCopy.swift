/// A copy of the text of changed blocks from one file of a comparison to the other, such as
/// Copy to Right or Copy All Changes to Left.
///
/// The file that takes the text replaces the lines of each block with the lines of the other
/// file, so that both are equal there under the comparison mode.
public struct ChangeCopy: Sendable, Hashable {
  /// Which blocks a copy takes.
  public enum Extent: Sendable, Hashable {
    /// The changed block with this ID.
    case block(Int)

    /// Every changed block, in one run.
    case allChanges
  }

  /// Which blocks the copy takes.
  public let extent: Extent

  /// The file whose text is copied.
  public let source: Role

  /// Copies the text of `block` from the file of `source` to the other file.
  ///
  /// - Precondition: `source` is A or B.
  public init(block: Block, from source: Role) {
    self.init(extent: .block(block.id), source: source)
  }

  /// Copies the text of every changed block from the file of `source` to the other file.
  ///
  /// - Precondition: `source` is A or B.
  public init(allChangesFrom source: Role) {
    self.init(extent: .allChanges, source: source)
  }

  private init(extent: Extent, source: Role) {
    precondition(source != .base, "A comparison copies between A and B")
    self.extent = extent
    self.source = source
  }

  /// The file that takes the text: the other file of the comparison.
  public var target: Role {
    source == .a ? .b : .a
  }
}
