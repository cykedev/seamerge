import Foundation
import MergeModel
import PaneKit

extension PaneContent {
  /// The content of the pane of `role`, one of the inputs of the merge, on the row grid of the
  /// panes above the result.
  ///
  /// - Parameters:
  ///   - changes: The changed blocks of the merge, which become the blocks of the content.
  ///   - document: The result, which tells which conflicts are still open.
  ///   - ignoredDifferences: The lines whose differences the comparison ignores, which get a ring
  ///     in the gutter.
  ///   - conflictMarkRole: The pane that carries the mark of a conflict.
  /// - Precondition: `role` takes part in the merge.
  init(
    source role: Role, of changes: SessionChanges, document: ResultDocument,
    ignoredDifferences: IgnoredDifferences, conflictMarkRole: Role
  ) {
    let session = changes.session
    let layout = session.rowLayout
    guard let displayText = layout.displayText(for: role), let file = session.file(for: role)
    else {
      preconditionFailure("The merge has no input \(role)")
    }
    guard layout.rowCount > 0 else {
      self = .empty
      return
    }
    var lineNumbers: [Int32] = []
    lineNumbers.reserveCapacity(layout.rowCount)
    for block in session.blocks {
      let lines = block.lines(in: role)
      for row in 0..<layout.rows(of: block).count {
        lineNumbers.append(row < lines.count ? Int32(lines.lowerBound + row) : -1)
      }
    }
    let endingsByLine = Self.lineEndings(of: file, lineCount: layout.lineCount(in: role))
    let lineEndings = lineNumbers.map { line in
      line < 0 ? LineEnding.none : endingsByLine[Int(line)]
    }
    let blocks = changes.blocks.map { block in
      let isOpen = document.segment(for: block).state == .open
      let carriesConflictMark = block.kind == .conflict && role == conflictMarkRole
      return PaneBlock(
        rows: layout.rows(of: block),
        style: changes.style(of: role, in: block, conflictIsOpen: isOpen),
        marker: changes.marker(of: role, in: block),
        conflict: carriesConflictMark ? (isOpen ? .open : .resolved) : nil)
    }
    let ignoredRows = IndexSet(
      ignoredDifferences.lines(in: role).map { layout.row(ofLine: $0, in: role) })
    self.init(
      text: displayText.string, lineNumbers: lineNumbers, blocks: blocks,
      ignoredDifferenceRows: ignoredRows, lineEndings: lineEndings)
  }

  /// How each of the `lineCount` lines of `file` ends.
  ///
  /// The lines are those of the comparison: they end at LF, or at CR in a file whose lines all
  /// end in CR. Where the file splits into another number of lines, as a comparison mode that
  /// also ends lines at a lone CR does, each line counts as ending like most lines of the file.
  static func lineEndings(of file: SourceFile, lineCount: Int) -> [LineEnding] {
    let text = Array(file.text?.utf16 ?? "".utf16)
    let separator = file.lineEndings == .cr ? Self.carriageReturn : Self.lineFeed
    var endings: [LineEnding] = []
    endings.reserveCapacity(lineCount)
    for (index, unit) in text.enumerated() where unit == separator {
      if separator == Self.carriageReturn {
        endings.append(.carriageReturn)
      } else {
        let afterReturn = index > 0 && text[index - 1] == Self.carriageReturn
        endings.append(afterReturn ? .carriageReturnLineFeed : .lineFeed)
      }
    }
    if text.last != separator && !text.isEmpty {
      endings.append(.none)
    }
    guard endings.count == lineCount else {
      let usual: LineEnding =
        switch file.lineEndings {
        case .crlf: .carriageReturnLineFeed
        case .cr: .carriageReturn
        case .lf, .mixed, nil: .lineFeed
        }
      return Array(repeating: usual, count: lineCount)
    }
    return endings
  }

  private static let lineFeed = UInt16(UInt8(ascii: "\n"))
  private static let carriageReturn = UInt16(UInt8(ascii: "\r"))
}
