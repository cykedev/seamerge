/// The correspondence between rows of the panes above and lines of the result, block by block.
///
/// A position in either is a block and how far through it the position lies; the matching
/// position in the other is the same block, the same fraction through. Positions are fractional,
/// so that a pane can match another's position at its reading line exactly. A block whose segment
/// has no lines lies at a single position of the result. A map describes one state of the
/// result; after the text changes, make a new one.
public struct ScrollMap: Sendable {
  /// The first row of each block, followed by the number of rows.
  private let rowStarts: [Int]

  /// The first line of the result in each block's segment, followed by the number of lines.
  private let lineStarts: [Int]

  /// Creates the map for `document` and its text.
  ///
  /// The result's lines end at CR, LF, CRLF, NEL, U+2028 and U+2029, as the text system breaks
  /// them; a segment that starts within a line starts on that line.
  ///
  /// - Parameter text: The result text, as long as the segments together.
  public init(document: ResultDocument, text: String) {
    let rowLayout = document.session.rowLayout
    rowStarts =
      document.session.blocks.map { rowLayout.rows(of: $0).lowerBound } + [rowLayout.rowCount]
    var lineStarts: [Int] = []
    lineStarts.reserveCapacity(document.segments.count + 1)
    var line = 0
    var previous: UInt16 = 0
    for segmentText in document.split(text) {
      lineStarts.append(line)
      for unit in segmentText.utf16 {
        if Self.isLineBreak(unit) && !(unit == Self.lineFeed && previous == Self.carriageReturn) {
          line += 1
        }
        previous = unit
      }
    }
    lineStarts.append(line)
    self.lineStarts = lineStarts
  }

  /// The line of the result at the same position as `row` of the panes above.
  public func resultLine(atRow row: Double) -> Double {
    Self.position(row, from: rowStarts, to: lineStarts)
  }

  /// The row of the panes above at the same position as `line` of the result.
  public func row(atResultLine line: Double) -> Double {
    Self.position(line, from: lineStarts, to: rowStarts)
  }

  /// Maps `position`, measured against the block starts `source`, to the block starts `target`.
  ///
  /// The position lies in the last block that starts at or before it; a block without extent
  /// in `source` is passed over, because the block after it starts at the same place. Before the
  /// first block and past the last, positions map one to one.
  private static func position(_ position: Double, from source: [Int], to target: [Int]) -> Double {
    let blockCount = source.count - 1
    guard blockCount > 0, position >= 0 else { return position }
    guard position < Double(source[blockCount]) else {
      return Double(target[blockCount]) + position - Double(source[blockCount])
    }
    var low = 0
    var high = blockCount
    while high - low > 1 {
      let middle = (low + high) / 2
      if Double(source[middle]) <= position { low = middle } else { high = middle }
    }
    let fraction = (position - Double(source[low])) / Double(source[low + 1] - source[low])
    return Double(target[low]) + fraction * Double(target[low + 1] - target[low])
  }

  private static let lineFeed = UInt16(UInt8(ascii: "\n"))
  private static let carriageReturn = UInt16(UInt8(ascii: "\r"))

  /// Whether a UTF-16 code unit ends a line in the text system.
  private static func isLineBreak(_ unit: UInt16) -> Bool {
    unit == lineFeed || unit == carriageReturn || unit == 0x85 || unit == 0x2028 || unit == 0x2029
  }
}
