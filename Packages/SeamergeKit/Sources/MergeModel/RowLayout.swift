import Synchronization
import TextBasics

/// The row grid that aligns the blocks of a session across the panes.
///
/// Each block takes as many rows as its longest range has lines and starts on the same row in
/// every pane. Within a block, a pane shows its own lines first and fills the remaining rows
/// with filler rows, which belong to no line. Lookups in either direction take logarithmic time.
public struct RowLayout: Sendable {
  /// The blocks of the session.
  private let blocks: [Block]

  /// The first row of each block, followed by the number of rows.
  private let blockRowStarts: [Int]

  /// The number of lines of each input that takes part.
  private let lineCounts: [Role: Int]

  /// The text of each pane on the grid, until the grid lets go of it.
  private let displayTexts: PaneTexts

  /// The inputs that take part, whose lines the texts without filler rows show.
  private let files: [Role: ComparedFile]

  /// Lays out `blocks` and the lines of `files` on one grid.
  init(blocks: [Block], files: [Role: ComparedFile]) {
    var blockRowStarts = [0]
    blockRowStarts.reserveCapacity(blocks.count + 1)
    for block in blocks {
      blockRowStarts.append(blockRowStarts[blockRowStarts.count - 1] + block.rowCount)
    }
    self.blocks = blocks
    self.blockRowStarts = blockRowStarts
    lineCounts = files.mapValues(\.lineCount)
    self.files = files
    displayTexts = PaneTexts(Self.displayTexts(of: files, on: blocks))
  }

  /// The text of the pane of each of `files` on the rows of `blocks`.
  private static func displayTexts(
    of files: [Role: ComparedFile], on blocks: [Block]
  ) -> [Role: DisplayText] {
    Dictionary(
      uniqueKeysWithValues: files.map { role, file in
        (role, DisplayText(file: file, role: role, blocks: blocks))
      })
  }

  /// The number of rows.
  public var rowCount: Int { blockRowStarts[blockRowStarts.count - 1] }

  /// The text of the pane of `role`, or `nil` if the input does not take part.
  ///
  /// After ``letGoOfDisplayTexts()``, the first request lays out the texts anew, in time
  /// proportional to the size of the files.
  public func displayText(for role: Role) -> DisplayText? {
    displayTexts.texts { [blocks, files] in Self.displayTexts(of: files, on: blocks) }[role]
  }

  /// Lets go of the texts of the panes, which every copy of the grid shares, until they are asked
  /// for again: the grid of a comparison that is no longer shown, as one that undo may bring
  /// back, then takes no more memory than its rows and lines.
  public func letGoOfDisplayTexts() {
    displayTexts.letGo()
  }

  /// Whether `other` is a copy of this grid, which shares the texts of its panes.
  public func sharesDisplayTexts(with other: RowLayout) -> Bool {
    displayTexts === other.displayTexts
  }

  /// The text of the input of `role` with one row per line and no filler rows, or `nil` if the
  /// input does not take part: what a pane shows that connects its changes to its neighbors'
  /// rather than lining up its rows with theirs.
  ///
  /// Row *r* of the text shows line *r*; the lines of a block are ``Block/lines(in:)``. The text
  /// is laid out anew on each call, in time proportional to the size of the file.
  public func lineText(for role: Role) -> DisplayText? {
    files[role].map(DisplayText.init(linesOf:))
  }

  /// Where each block starts on `side`, followed by where the last one ends: in rows of the grid,
  /// or in lines of an input.
  func blockStarts(on side: ScrollMap.Side) -> [Int] {
    switch side {
    case .grid:
      return blockRowStarts
    case .lines(let role):
      return blocks.map { $0.lines(in: role).lowerBound } + [lineCount(in: role)]
    }
  }

  /// The number of lines of the input of `role`, or 0 if it does not take part.
  public func lineCount(in role: Role) -> Int {
    lineCounts[role] ?? 0
  }

  /// The rows of a block.
  ///
  /// - Precondition: `block` is one of the blocks the grid was laid out for.
  public func rows(of block: Block) -> Range<Int> {
    precondition(blocks.indices.contains(block.id), "Block \(block.id) is not on the grid")
    return blockRowStarts[block.id]..<blockRowStarts[block.id + 1]
  }

  /// The block that a row belongs to.
  ///
  /// - Precondition: `row` lies within `0..<rowCount`.
  public func block(atRow row: Int) -> Block {
    precondition((0..<rowCount).contains(row), "Row \(row) is out of range")
    return blocks[blocks.indices.lastIndex(holding: { blockRowStarts[$0] <= row })]
  }

  /// The line of the input of `role` that a row shows, or `nil` for a filler row.
  ///
  /// - Precondition: `row` lies within `0..<rowCount`.
  public func line(atRow row: Int, in role: Role) -> Int? {
    let block = block(atRow: row)
    let lines = block.lines(in: role)
    let offset = row - blockRowStarts[block.id]
    return offset < lines.count ? lines.lowerBound + offset : nil
  }

  /// The row that shows a line of the input of `role`.
  ///
  /// - Precondition: `line` lies within `0..<lineCount(in: role)`.
  public func row(ofLine line: Int, in role: Role) -> Int {
    precondition((0..<lineCount(in: role)).contains(line), "Line \(line) is out of range")
    // Blocks without lines in this input start where the next block does, so the last block
    // starting at or before the line is the one that contains it.
    let index = blocks.indices.lastIndex(holding: { blocks[$0].lines(in: role).lowerBound <= line })
    return blockRowStarts[index] + line - blocks[index].lines(in: role).lowerBound
  }
}

/// The texts of the panes of a grid, shared by its copies: kept until the grid lets go of them,
/// and laid out anew on the first request after.
private final class PaneTexts: Sendable {
  private let texts: Mutex<[Role: DisplayText]?>

  init(_ texts: [Role: DisplayText]) {
    self.texts = Mutex(texts)
  }

  /// The texts, laid out by `make` if the grid let go of them.
  func texts(orMake make: () -> [Role: DisplayText]) -> [Role: DisplayText] {
    texts.withLock { texts in
      if let texts { return texts }
      let made = make()
      texts = made
      return made
    }
  }

  func letGo() {
    texts.withLock { $0 = nil }
  }
}
