import Foundation
import MergeModel
import PaneKit
import TextBasics

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

  /// Lays out the text of `result` with the changed blocks of the merge.
  ///
  /// - Parameter headers: The headers of the inputs, whose names the help tags of the toggles use.
  init(result: ResultState, changes: SessionChanges, headers: [Role: SideHeader]) {
    let document = result.document
    let text = result.text
    let rows = result.rows
    var blocks: [PaneBlock] = []
    var previews: [PanePreview] = []
    var decisions: [Int: BlockDecision] = [:]
    blocks.reserveCapacity(changes.blocks.count)
    var segmentStart = 0
    var changedIndex = 0
    // Where the segments of unchanged blocks lie in the text, which show no tint unless typed in.
    var unchangedSegments: [Range<Int>] = []
    for (block, segment) in zip(document.session.blocks, document.segments) {
      defer { segmentStart += segment.length }
      guard changedIndex < changes.blocks.count, changes.blocks[changedIndex] == block else {
        unchangedSegments.append(segmentStart..<segmentStart + segment.length)
        continue
      }
      let blockRows = rows.rows(ofUTF16: segmentStart..<segmentStart + segment.length)
      blocks.append(PaneBlock(rows: blockRows, style: Self.rowStyle(of: segment)))
      if segment.state == .open {
        previews += Self.previews(
          of: block, in: document,
          startingAt: result.resultText.paneOffset(ofFileOffset: segmentStart),
          row: blockRows.lowerBound, in: rows)
      }
      decisions[changedIndex] = Self.decision(
        for: segment, toggles: document.toggles(in: block), canReset: document.canReset(block),
        headers: headers)
      changedIndex += 1
    }
    // Each line of a block with lines from several places in the tint of its own: gray where it
    // was typed by hand, and otherwise the tint its source has in the block without the typing,
    // which in an unchanged block is none.
    var rowTints: [Int: BlockStyle] = [:]
    var unchanged = unchangedSegments.makeIterator()
    var nextUnchanged = unchanged.next()
    for origin in document.lineOrigins(of: text) {
      while let segment = nextUnchanged, segment.upperBound <= origin.range.lowerBound {
        nextUnchanged = unchanged.next()
      }
      let isInUnchangedBlock = nextUnchanged?.contains(origin.range.lowerBound) == true
      guard origin.roles.isEmpty || !isInUnchangedBlock else { continue }
      let tint = origin.roles.isEmpty ? BlockStyle.handwritten : Self.style(ofSources: origin.roles)
      for row in rows.rows(ofUTF16: origin.range) {
        rowTints[row] = tint
      }
    }
    content = PaneContent(
      text: rows.text, lineNumbers: rows.lineEndings.indices.map(Int32.init),
      blocks: blocks, lineEndings: rows.lineEndings, previews: previews, rowTints: rowTints)
    self.decisions = decisions
  }

  /// The style of a segment as its mark in the overview bar shows it: in the color of the
  /// source of its text, red while open, and gray once edited by hand.
  static func style(of segment: Segment) -> BlockStyle {
    switch segment.state {
    case .open: .tinted(.conflict)
    case .edited: .handwritten
    case .untouched, .auto, .chosen: style(ofSources: segment.sources)
    }
  }

  /// How the rows of `segment` are tinted: in the color of the source of its text, red while
  /// open.
  ///
  /// An edited segment keeps the color of its sources; its lines that come from several places
  /// take the tints of their own (``ResultDocument/lineOrigins(of:)``).
  private static func rowStyle(of segment: Segment) -> BlockStyle {
    segment.state == .edited ? style(ofSources: segment.sources) : style(of: segment)
  }

  /// The tint of text taken from `sources`.
  static func style(ofSources sources: [Role]) -> BlockStyle {
    let sources = Set(sources)
    if sources.isSuperset(of: [.a, .b]) { return .combined }
    if sources.contains(.a) { return .tinted(.a) }
    if sources.contains(.b) { return .tinted(.b) }
    if sources.contains(.base) { return .original }
    return .unchanged
  }

  /// The previews of an open conflict of `document` that starts at `offset` of the pane's text,
  /// in `row`: first A's lines, then B's, each side's removal note in place of lines it removed.
  ///
  /// Where typing removed the line break before the conflict, its preview starts within the row.
  private static func previews(
    of block: Block, in document: ResultDocument, startingAt offset: Int, row: Int, in rows: Rows
  ) -> [PanePreview] {
    var previews: [PanePreview] = []
    var start = row
    var lower = offset
    for (role, color) in [(Role.a, ColorRole.a), (.b, .b)] {
      let end = start + document.previewLineCount(of: role, in: block)
      // At the end of the text, the last line of the preview has no line feed in the rows, and
      // a preview of one empty line there has no text at all.
      let length = rows.starts[rows.starts.lineCount] - 1
      let upper = min(rows.starts[end], length)
      let range = min(max(rows.starts[start], lower), upper)..<upper
      lower = upper
      if !range.isEmpty {
        previews.append(PanePreview(range: range, role: color))
      }
      start = end
    }
    return previews
  }

  /// What the decision column shows for a block whose segment is `segment`, with the arrow that
  /// resets it if `canReset`.
  private static func decision(
    for segment: Segment, toggles: [Toggle], canReset: Bool, headers: [Role: SideHeader]
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
      canReset: canReset)
  }

  /// What switching `toggle` on does, with the real names of its inputs.
  private static func help(for toggle: Toggle, headers: [Role: SideHeader]) -> String {
    let sides = toggle.roles.filter { $0 != .base }.compactMap { headers[$0]?.distinctName }
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
        localized: "Remove these lines, as \(names) did.", bundle: .module,
        comment:
          "Help tag of a toggle that removes the lines, such as Remove these lines, as main did.")
    }
  }

  /// The text of the result split into rows: separated by line feeds, with how each line ended.
  struct Rows {
    /// The text with every line break replaced by a line feed.
    let text: String

    /// The UTF-16 offset in ``text`` where each row starts, followed by the length of the text
    /// plus one, as if the last row ended with a line feed too.
    let starts: LineStarts

    /// How the line of each row ended in the result.
    let lineEndings: [LineEnding?]

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

    /// The row in which `offset` of ``text`` lies; the end of the text lies in the last row.
    func row(ofPaneOffset offset: Int) -> Int {
      starts.line(containing: offset)
    }

    /// The row whose line, its break included, holds offset `offset` of the result text, or the
    /// number of rows for an offset after the last line break that ends the text.
    private func row(containing offset: Int) -> Int {
      breakOffsets.partitioningIndex { $0 >= offset }
    }

    init(text: String, starts: LineStarts, lineEndings: [LineEnding?], breakOffsets: [Int]) {
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
    var starts = [0]
    var lineEndings: [LineEnding?] = []
    var breakOffsets: [Int] = []
    // UTF-16 offsets into the text, and into the pane's text, which has one unit for CRLF.
    var offset = 0
    var paneOffset = 0
    var hasOtherBreaks = false
    var utf8 = Array(text.utf8)
    utf8.append(0)
    var index = 0
    while index < utf8.count - 1 {
      let byte = utf8[index]
      var ending: LineEnding?
      var length = 1
      var units = 1
      switch byte {
      case 0x0A: ending = .lf
      case 0x0D where utf8[index + 1] == 0x0A:
        ending = .crlf
        length = 2
        units = 2
      case 0x0D: ending = .cr
      case 0xC2 where utf8[index + 1] == 0x85:
        ending = .lf
        length = 2
      case 0xE2
      where utf8[index + 1] == 0x80 && (utf8[index + 2] == 0xA8 || utf8[index + 2] == 0xA9):
        ending = .lf
        length = 3
      case 0x80..<0xC0: units = 0
      case 0xF0...: units = 2
      default: break
      }
      index += length
      guard let ending else {
        offset += units
        paneOffset += units
        continue
      }
      hasOtherBreaks = hasOtherBreaks || byte != 0x0A
      // The last unit of the break, so that a part of the text ending with the break ends in
      // its row.
      breakOffsets.append(offset + units - 1)
      lineEndings.append(ending)
      offset += units
      paneOffset += 1
      starts.append(paneOffset)
    }
    let endsWithBreak = starts.count > 1 && starts[starts.count - 1] == paneOffset
    if !endsWithBreak {
      lineEndings.append(nil)
      breakOffsets.append(offset)
      starts.append(paneOffset + 1)
    }
    let paneText: String
    if !hasOtherBreaks {
      // Every line break is a line feed already; the pane leaves out the one that ends the text.
      paneText = endsWithBreak ? String(text.utf8.dropLast()) ?? "" : text
    } else {
      paneText = String(ResultText.visibleForm(of: text).utf8.dropLast(endsWithBreak ? 1 : 0)) ?? ""
    }
    return Rows(
      text: paneText, starts: LineStarts(starts), lineEndings: lineEndings,
      breakOffsets: breakOffsets)
  }

}
