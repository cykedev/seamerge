/// The correspondence between positions in two ways of counting the text of a session, block by
/// block: rows of the grid and lines of the result, or the lines of two inputs.
///
/// A position on either side is a block and how far through it the position lies; the matching
/// position on the other side is the same block, the same fraction through. Positions are
/// fractional, so that a pane can match another's position at its reading line exactly. A block
/// without extent on one side lies at a single position there. A map with the result describes
/// one state of the result; after the text changes, make a new one.
public struct ScrollMap: Sendable {
  /// A way of counting positions in the text of a session.
  public enum Side: Sendable, Hashable {
    /// Rows of the grid on which the panes side by side line up.
    case grid
    /// Lines of the input of a role, as a pane shows them without filler rows.
    case lines(Role)
  }

  /// Where each block starts on the source side, followed by where the last one ends.
  private let sourceStarts: [Int]

  /// Where each block starts on the target side, followed by where the last one ends.
  private let targetStarts: [Int]

  /// Creates the map from rows of the grid to lines of `document` and its text.
  ///
  /// The result's lines end at CR, LF, CRLF, NEL, U+2028 and U+2029, as the text system breaks
  /// them; a segment that starts within a line starts on that line.
  ///
  /// - Parameter text: The result text, as long as the segments together.
  public init(document: ResultDocument, text: String) {
    sourceStarts = document.session.rowLayout.blockStarts(on: .grid)
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
    targetStarts = lineStarts
  }

  /// Creates the map from `source` to `target` in the text of `session`.
  ///
  /// - Precondition: The inputs of both sides take part in the session.
  public init(session: Session, from source: Side, to target: Side) {
    for case .lines(let role) in [source, target] {
      precondition(session.file(for: role) != nil, "The session has no input \(role)")
    }
    sourceStarts = session.rowLayout.blockStarts(on: source)
    targetStarts = session.rowLayout.blockStarts(on: target)
  }

  /// The position on the target side at the same place as `position` on the source side.
  public func targetPosition(at position: Double) -> Double {
    Self.position(position, from: sourceStarts, to: targetStarts)
  }

  /// The position on the source side at the same place as `position` on the target side.
  public func sourcePosition(at position: Double) -> Double {
    Self.position(position, from: targetStarts, to: sourceStarts)
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
