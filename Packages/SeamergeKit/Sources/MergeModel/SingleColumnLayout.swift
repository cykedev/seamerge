import TextBasics

/// The rows of a comparison laid out in a single column: the lines that both files share once,
/// and in each changed block the lines of one file above those of the other.
///
/// The layout follows from the blocks of the session, block by block and in their order, so the
/// blocks start in the column in the same order as on the row grid. An unchanged block shows
/// each pair of lines on one row, in the text of the second side; where it has more lines on one
/// side, as lines that ignore rules match entirely may, those follow on rows of their own. A
/// changed block shows the lines of the first side, then those of the second. Every row shows a
/// line; there are no filler rows. Lookups in either direction take logarithmic time.
///
/// A layout describes one session and does not change with it: once the files are loaded again
/// or compared in another mode, which makes a new session, its owner lays out the new session.
public struct SingleColumnLayout: Sendable {
  /// What a row shows: the block it belongs to and its line on each side that has one.
  public struct Place: Sendable, Hashable {
    /// The block that the row belongs to.
    public let block: Block

    /// The line of A that the row shows, if any.
    private let lineOfA: Int?

    /// The line of B that the row shows, if any.
    private let lineOfB: Int?

    /// Creates the place of a row of `block` that shows `line` of `role`, and `sharedLine` of the
    /// other side if the sides share the line.
    fileprivate init(block: Block, line: Int, of role: Role, sharedLine: Int?) {
      self.block = block
      lineOfA = role == .a ? line : sharedLine
      lineOfB = role == .b ? line : sharedLine
    }

    /// The zero-based line of the input of `role` that the row shows, or `nil` if it shows none
    /// of that input.
    public func line(in role: Role) -> Int? {
      switch role {
      case .a: lineOfA
      case .b: lineOfB
      case .base: nil
      }
    }

    /// The only side whose line the row shows, or `nil` for a line that both sides share.
    public var side: Role? {
      switch (lineOfA, lineOfB) {
      case (_?, nil): .a
      case (nil, _?): .b
      default: nil
      }
    }
  }

  /// The side whose lines come first in a changed block: A, the older file, or B after Swap
  /// Sides.
  ///
  /// Unchanged rows show the text of the other side.
  public let firstSide: Role

  /// The text of the rows, each the line it shows without the line ending.
  public let displayText: DisplayText

  /// The side whose lines come second in a changed block.
  private let secondSide: Role

  /// The blocks of the session.
  private let blocks: [Block]

  /// The first row of each block, followed by the number of rows.
  private let blockRowStarts: [Int]

  /// The number of lines of each side.
  private let lineCounts: [Role: Int]

  /// The row grid of the session, whose rows the inline highlights and the collapsed runs name.
  let rowLayout: RowLayout

  /// Lays out the comparison `session` in a single column, with the lines of `firstSide` first
  /// in each changed block.
  ///
  /// The text is laid out at once, in time proportional to the size of the files.
  ///
  /// - Precondition: `session` is a comparison, and `firstSide` is one of its sides.
  public init(session: Session, firstSide: Role = .a) {
    precondition(session.kind == .diff, "Only a comparison shows in a single column")
    precondition(firstSide != .base, "A comparison has no base")
    let files = session.files
    let (first, second) = firstSide == .a ? (files.a, files.b) : (files.b, files.a)
    self.firstSide = firstSide
    secondSide = firstSide.other
    blocks = session.blocks
    rowLayout = session.rowLayout
    lineCounts = [.a: session.rowLayout.lineCount(in: .a), .b: session.rowLayout.lineCount(in: .b)]
    var blockRowStarts = [0]
    blockRowStarts.reserveCapacity(blocks.count + 1)
    for block in blocks {
      blockRowStarts.append(
        blockRowStarts[blockRowStarts.count - 1] + block.lines(in: firstSide).count
          + block.lines(in: firstSide.other).count - Self.sharedRowCount(of: block))
    }
    self.blockRowStarts = blockRowStarts
    var rows: [DisplayText.RowSource?] = []
    rows.reserveCapacity(blockRowStarts[blockRowStarts.count - 1])
    for block in blocks {
      let shared = Self.sharedRowCount(of: block)
      let secondLines = block.lines(in: secondSide)
      for line in secondLines.prefix(shared) {
        rows.append(DisplayText.RowSource(file: 1, line: line))
      }
      for line in block.lines(in: firstSide).dropFirst(shared) {
        rows.append(DisplayText.RowSource(file: 0, line: line))
      }
      for line in secondLines.dropFirst(shared) {
        rows.append(DisplayText.RowSource(file: 1, line: line))
      }
    }
    displayText = DisplayText(
      files: [first, second], rows: rows, rowCount: blockRowStarts[blockRowStarts.count - 1])
  }

  /// The number of rows of `block` that show a line both sides share: every pair of lines of an
  /// unchanged block, none of a changed one.
  private static func sharedRowCount(of block: Block) -> Int {
    block.kind == .unchanged ? min(block.a.count, block.b.count) : 0
  }

  /// The number of rows.
  public var rowCount: Int { blockRowStarts[blockRowStarts.count - 1] }

  /// The rows of a block.
  ///
  /// - Precondition: `block` is one of the blocks of the session.
  public func rows(of block: Block) -> Range<Int> {
    precondition(blocks.indices.contains(block.id), "Block \(block.id) is not in the column")
    return blockRowStarts[block.id]..<blockRowStarts[block.id + 1]
  }

  /// The rows of a block that show lines of `role` alone: in a changed block the part of that
  /// side, in an unchanged block the lines that side has more than the other.
  ///
  /// - Precondition: `block` is one of the blocks of the session, and `role` is one of its sides.
  public func rows(of block: Block, showingOnly role: Role) -> Range<Int> {
    precondition(role != .base, "A comparison has no base")
    let start = rows(of: block).lowerBound
    let shared = Self.sharedRowCount(of: block)
    let firstCount = block.lines(in: firstSide).count
    if role == firstSide {
      return start + shared..<start + firstCount
    }
    return start + firstCount..<start + firstCount + block.lines(in: role).count - shared
  }

  /// What `row` shows.
  ///
  /// - Precondition: `row` lies within `0..<rowCount`.
  public func place(atRow row: Int) -> Place {
    precondition((0..<rowCount).contains(row), "Row \(row) is out of range")
    let block = blocks[blocks.indices.lastIndex(holding: { blockRowStarts[$0] <= row })]
    let offset = row - blockRowStarts[block.id]
    let shared = Self.sharedRowCount(of: block)
    let firstLines = block.lines(in: firstSide)
    let secondLines = block.lines(in: secondSide)
    if offset < shared {
      return Place(
        block: block, line: firstLines.lowerBound + offset, of: firstSide,
        sharedLine: secondLines.lowerBound + offset)
    }
    if offset < firstLines.count {
      return Place(
        block: block, line: firstLines.lowerBound + offset, of: firstSide, sharedLine: nil)
    }
    return Place(
      block: block, line: secondLines.lowerBound + shared + offset - firstLines.count,
      of: secondSide, sharedLine: nil)
  }

  /// The row that shows a line of the input of `role`: a row of its own, or the row it shares
  /// with the line of the other side.
  ///
  /// - Precondition: `role` is a side of the comparison, and `line` lies within
  ///   `0..<lineCount(in: role)`.
  public func row(ofLine line: Int, in role: Role) -> Int {
    precondition(role != .base, "A comparison has no base")
    precondition((0..<(lineCounts[role] ?? 0)).contains(line), "Line \(line) is out of range")
    // Blocks without lines in this input start where the next block does, so the last block
    // starting at or before the line is the one that contains it.
    let index = blocks.indices.lastIndex(holding: { blocks[$0].lines(in: role).lowerBound <= line })
    let block = blocks[index]
    let offset = line - block.lines(in: role).lowerBound
    let shared = Self.sharedRowCount(of: block)
    guard role == secondSide, offset >= shared else { return blockRowStarts[index] + offset }
    return blockRowStarts[index] + block.lines(in: firstSide).count + offset - shared
  }

  /// The row of the grid that shows the same line as `row` of an unchanged block: the rows of an
  /// unchanged block lie in the same order in the column and on the grid.
  ///
  /// - Precondition: `row` belongs to an unchanged block.
  func gridRow(ofUnchangedRow row: Int) -> Int {
    let block = place(atRow: row).block
    precondition(block.kind == .unchanged, "Row \(row) belongs to a changed block")
    return rowLayout.rows(of: block).lowerBound + row - blockRowStarts[block.id]
  }
}

extension Role {
  /// The other side of a comparison.
  fileprivate var other: Role {
    switch self {
    case .a: .b
    case .b, .base: .a
    }
  }
}
