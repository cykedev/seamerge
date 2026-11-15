/// The arrow in the gutter at one end of a move, which points to the other end and takes the
/// place of the mark of how the side changed the block.
///
/// Lines that moved are still lines removed in one place and added in another; the arrow tells
/// that they are the same lines, and where the others are.
public struct MoveMark: Sendable, Hashable {
  /// Which end of the move a block is.
  public enum End: Sendable, Hashable {
    /// The place the lines left.
    case source
    /// The place the lines arrived at.
    case destination
  }

  /// Which end of the move the block is.
  public var end: End

  /// The index of the block at the other end, among the blocks of every pane, which the arrow
  /// points to.
  public var otherBlock: Int

  /// The zero-based number of the first line of the other end, in the file that shows it.
  public var otherLine: Int

  /// Creates the mark of the end `end` of a move whose other end is the block `otherBlock`,
  /// starting at the zero-based line `otherLine` of its file.
  public init(end: End, otherBlock: Int, otherLine: Int) {
    self.end = end
    self.otherBlock = otherBlock
    self.otherLine = otherLine
  }

  /// Whether the arrow of the block at `index` points down: the other end lies below it.
  func pointsDown(fromBlock index: Int) -> Bool {
    otherBlock > index
  }
}
