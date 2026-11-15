import AppKit

/// The horizontal places of the characters of a laid-out line, found in one pass.
///
/// `NSTextLineFragment.locationForCharacter(at:)` walks the line from its start each time, so
/// drawing the highlights or the invisible characters of a long line would take time in
/// proportion to its length times their number. A long line asks Core Text for the places of all
/// its characters at once; a short line asks TextKit, which is exact and quick there.
struct LineCarets {
  private let line: NSTextLineFragment
  private let offsets: [CGFloat?]

  /// The places of the characters of `line`.
  init(_ line: NSTextLineFragment) {
    self.line = line
    let range = line.characterRange
    guard range.length > Self.shortLineLength else {
      offsets = []
      return
    }
    var offsets = [CGFloat?](repeating: nil, count: range.length)
    let typeset = CTLineCreateWithAttributedString(
      line.attributedString.attributedSubstring(from: range))
    CTLineEnumerateCaretOffsets(typeset) { offset, index, isLeadingEdge, _ in
      if isLeadingEdge, offsets.indices.contains(index), offsets[index] == nil {
        offsets[index] = CGFloat(offset)
      }
    }
    self.offsets = offsets
  }

  /// The distance from the start of the line to the leading edge of the character at `index`,
  /// an offset into the paragraph like those of `characterRange`, or to the end of the line.
  func x(at index: Int) -> CGFloat {
    let local = index - line.characterRange.location
    if offsets.indices.contains(local), let offset = offsets[local] {
      return offset
    }
    return line.locationForCharacter(at: index).x
  }

  /// The length up to which a line asks TextKit for each place.
  private static let shortLineLength = 256
}
