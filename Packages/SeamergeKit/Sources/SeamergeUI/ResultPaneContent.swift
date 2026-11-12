import Foundation
import MergeModel
import PaneKit

/// What the result pane shows: the text of the result, a block for each changed block of the
/// merge, the previews of open conflicts, and what the decision column shows for each block.
///
/// The result has rows of its own, one per line of its text. A block whose segment has no lines,
/// such as a removal both sides agree on, takes no rows and lies on the boundary where its lines
/// would be.
struct ResultPaneContent {
  /// The content of the result pane.
  let content: PaneContent

  /// What the decision column shows, by the index of the block among the changed blocks.
  let decisions: [Int: BlockDecision]

  /// Lays out `text`, the text of `document`, with the changed blocks of the merge.
  ///
  /// - Parameter headers: The headers of the inputs, whose names the help tags of the toggles use.
  /// - Precondition: `text` is as long as the segments of `document` together.
  init(
    document: ResultDocument, text: String, changes: SessionChanges, headers: [Role: SideHeader]
  ) {
    let rows = Self.rows(of: text)
    var blocks: [PaneBlock] = []
    var previews: [PanePreview] = []
    var decisions: [Int: BlockDecision] = [:]
    blocks.reserveCapacity(changes.blocks.count)
    var segmentStart = 0
    var changedIndex = 0
    for (block, segment) in zip(document.session.blocks, document.segments) {
      defer { segmentStart += segment.length }
      guard changedIndex < changes.blocks.count, changes.blocks[changedIndex] == block else {
        continue
      }
      let blockRows = rows.rows(ofUTF16: segmentStart..<segmentStart + segment.length)
      blocks.append(PaneBlock(rows: blockRows, style: Self.style(of: segment)))
      if segment.state == .open {
        previews += Self.previews(of: block, startingAt: blockRows.lowerBound, in: rows)
      }
      decisions[changedIndex] = Self.decision(
        for: segment, toggles: document.toggles(in: block), headers: headers)
      changedIndex += 1
    }
    content = PaneContent(
      text: rows.text, lineNumbers: rows.lineEndings.indices.map(Int32.init),
      blocks: blocks, lineEndings: rows.lineEndings, previews: previews)
    self.decisions = decisions
  }

  /// How the rows of a segment are tinted: in the color of the source of its text.
  static func style(of segment: Segment) -> BlockStyle {
    switch segment.state {
    case .open: return .tinted(.conflict)
    case .edited: return .handwritten
    case .untouched, .auto, .chosen: break
    }
    let sources = Set(segment.sources)
    if sources.isSuperset(of: [.a, .b]) { return .combined }
    if sources.contains(.a) { return .tinted(.a) }
    if sources.contains(.b) { return .tinted(.b) }
    if sources.contains(.base) { return .original }
    return .unchanged
  }

  /// The previews of an open conflict that starts at `row`: first A's lines, then B's.
  private static func previews(
    of block: Block, startingAt row: Int, in rows: Rows
  ) -> [PanePreview] {
    var previews: [PanePreview] = []
    var start = row
    for (role, color) in [(Role.a, ColorRole.a), (.b, .b)] {
      let end = start + block.lines(in: role).count
      // At the end of the text, the last line of the preview has no line feed in the rows, and
      // a preview of one empty line there has no text at all.
      let length = rows.starts[rows.starts.count - 1] - 1
      let upper = min(rows.starts[end], length)
      let range = min(rows.starts[start], upper)..<upper
      if !range.isEmpty {
        previews.append(PanePreview(range: range, role: color))
      }
      start = end
    }
    return previews
  }

  /// What the decision column shows for a block whose segment is `segment`.
  private static func decision(
    for segment: Segment, toggles: [Toggle], headers: [Role: SideHeader]
  ) -> BlockDecision {
    let state: BlockDecision.State =
      switch segment.state {
      case .untouched: .unchanged
      case .auto: .automatic(segment.sources.map(\.colorRole))
      case .chosen: .chosen(segment.sources.map(\.colorRole))
      case .edited: .edited
      case .open: .open
      }
    let sources = Set(segment.sources)
    return BlockDecision(
      state: state,
      toggles: toggles.map { toggle in
        DecisionToggle(
          roles: toggle.roles.map(\.colorRole),
          isOn: segment.state != .open && sources.isSuperset(of: toggle.roles),
          isDeletion: toggle.kind == .deletion,
          help: help(for: toggle, headers: headers))
      },
      canReset: segment.state == .chosen || segment.state == .edited)
  }

  /// What switching `toggle` on does, with the real names of its inputs.
  private static func help(for toggle: Toggle, headers: [Role: SideHeader]) -> String {
    let sides = toggle.roles.filter { $0 != .base }.compactMap { headers[$0]?.name }
    let names: String =
      switch sides.count {
      case 0:
        String(
          localized: "the base", bundle: .module,
          comment: "The common ancestor in the help tag of a toggle: Take the version of the base.")
      case 1: sides[0]
      default:
        String(
          localized: "\(sides[0]) and \(sides[1])", bundle: .module,
          comment: "Two sides that share a toggle, such as feature/login and main.")
      }
    switch toggle.kind {
    case .version:
      return String(
        localized: "Take the version of \(names).", bundle: .module,
        comment: "Help tag of a toggle, such as Take the version of feature/login.")
    case .deletion:
      return String(
        localized: "Take the deletion of \(names).", bundle: .module,
        comment: "Help tag of a toggle that removes the lines, such as Take the deletion of main.")
    }
  }

  /// The text of the result split into rows: separated by line feeds, with how each line ended.
  struct Rows {
    /// The text with every line break replaced by a line feed.
    let text: String

    /// The UTF-16 offset in ``text`` where each row starts, followed by the length of the text
    /// plus one, as if the last row ended with a line feed too.
    let starts: [Int]

    /// How the line of each row ended in the result.
    let lineEndings: [LineEnding]

    /// The UTF-16 offset in the result text of the last unit of the line break that ends each
    /// row, and for a last row without one, the length of the result text.
    private let breakOffsets: [Int]

    /// The rows that the part `range` of the result text takes: from the row it starts in to the
    /// row its last character lies in; an empty range takes no rows, and one at the end of a
    /// text that ends with a line break lies after the last row.
    func rows(ofUTF16 range: Range<Int>) -> Range<Int> {
      let first = row(containing: range.lowerBound)
      guard !range.isEmpty else { return first..<first }
      return first..<row(containing: range.upperBound - 1) + 1
    }

    /// The row whose line, its break included, holds offset `offset` of the result text, or the
    /// number of rows for an offset after the last line break that ends the text.
    private func row(containing offset: Int) -> Int {
      var low = 0
      var high = breakOffsets.count
      while low < high {
        let middle = (low + high) / 2
        if breakOffsets[middle] < offset { low = middle + 1 } else { high = middle }
      }
      return low
    }

    init(text: String, starts: [Int], lineEndings: [LineEnding], breakOffsets: [Int]) {
      self.text = text
      self.starts = starts
      self.lineEndings = lineEndings
      self.breakOffsets = breakOffsets
    }
  }

  /// Splits `text` into rows where the text system breaks lines: at CR, LF, CRLF, NEL, U+2028
  /// and U+2029, as the scroll map of the result counts them.
  ///
  /// A text that ends with a line break has no row after it; a text without any has one row.
  static func rows(of text: String) -> Rows {
    var units: [UInt16] = []
    units.reserveCapacity(text.utf16.count)
    var starts = [0]
    var lineEndings: [LineEnding] = []
    var breakOffsets: [Int] = []
    let source = Array(text.utf16)
    var index = 0
    while index < source.count {
      let unit = source[index]
      let ending: LineEnding?
      switch unit {
      case Self.carriageReturn where index + 1 < source.count && source[index + 1] == Self.lineFeed:
        ending = .carriageReturnLineFeed
      case Self.carriageReturn: ending = .carriageReturn
      case Self.lineFeed, 0x85, 0x2028, 0x2029: ending = .lineFeed
      default: ending = nil
      }
      guard let ending else {
        units.append(unit)
        index += 1
        continue
      }
      // The last unit of the break, so that a part of the text ending with the break ends in
      // its row.
      let breakEnd = ending == .carriageReturnLineFeed ? index + 1 : index
      breakOffsets.append(breakEnd)
      lineEndings.append(ending)
      units.append(Self.lineFeed)
      starts.append(units.count)
      index = breakEnd + 1
    }
    if units.last == Self.lineFeed {
      // The text ends with a line break; like the panes of the inputs, the result shows no
      // empty row after it.
      units.removeLast()
    } else {
      lineEndings.append(.none)
      breakOffsets.append(source.count)
      starts.append(units.count + 1)
    }
    return Rows(
      text: String(decoding: units, as: UTF16.self), starts: starts, lineEndings: lineEndings,
      breakOffsets: breakOffsets)
  }

  private static let lineFeed = UInt16(UInt8(ascii: "\n"))
  private static let carriageReturn = UInt16(UInt8(ascii: "\r"))
}
