import Foundation
import MergeModel
import PaneKit
import os

extension PaneContent {
  /// The content of the pane of `role`, one of the inputs of the session, on the row grid of the
  /// panes side by side.
  ///
  /// - Parameters:
  ///   - changes: The changed blocks of the session, which become the blocks of the content.
  ///   - lineEndings: How each line of the file ends, ``lineEndings(of:lineCount:)``.
  ///   - document: The result of a merge, which tells which conflicts are still open; `nil` for
  ///     a comparison.
  ///   - ignoredDifferences: The lines whose differences the comparison ignores, which get a ring
  ///     in the gutter.
  ///   - showsIgnoredPlaces: Whether the places where those lines differ are highlighted.
  ///   - baseIsShown: Whether the pane of the base is in view, which decides how the blocks are
  ///     tinted and which pane carries the mark of a conflict.
  /// - Precondition: `role` takes part in the session.
  init(
    source role: Role, of changes: SessionChanges, lineEndings endingsByLine: [LineEnding],
    document: ResultDocument?, ignoredDifferences: IgnoredDifferences, showsIgnoredPlaces: Bool,
    baseIsShown: Bool
  ) {
    let session = changes.session
    let layout = session.rowLayout
    guard let displayText = layout.displayText(for: role) else {
      preconditionFailure("The session has no input \(role)")
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
    let lineEndings = lineNumbers.map { line in
      line < 0 ? LineEnding.none : endingsByLine[Int(line)]
    }
    let blocks = Self.blocks(
      source: role, of: changes, document: document, baseIsShown: baseIsShown, alignsLines: true)
    let ignoredRows = IndexSet(
      ignoredDifferences.lines(in: role).map { layout.row(ofLine: $0, in: role) })
    let places =
      showsIgnoredPlaces
      ? Self.places(of: ignoredDifferences, in: role, of: session) {
        displayText.utf16Range(ofRow: layout.row(ofLine: $0, in: role)).lowerBound
      } : []
    self.init(
      text: displayText.string, lineNumbers: lineNumbers, blocks: blocks,
      ignoredDifferenceRows: ignoredRows, ignoredDifferencePlaces: places,
      lineEndings: lineEndings)
  }

  /// The content of the pane of `role`, one of the inputs of the session, with its file as it
  /// is: one row per line, without filler rows, and a block where the side has no lines marked
  /// by a hairline on the boundary where they are missing.
  ///
  /// - Parameters:
  ///   - text: The text of the input without filler rows, ``RowLayout/lineText(for:)``.
  ///   - changes: The changed blocks of the session, which become the blocks of the content.
  ///   - lineEndings: How each line of the file ends, ``lineEndings(of:lineCount:)``.
  ///   - document: The result of a merge, which tells which conflicts are still open; `nil` for
  ///     a comparison.
  ///   - ignoredDifferences: The lines whose differences the comparison ignores, which get a ring
  ///     in the gutter.
  ///   - showsIgnoredPlaces: Whether the places where those lines differ are highlighted.
  ///   - baseIsShown: Whether the pane of the base is in view, which decides how the blocks are
  ///     tinted and which pane carries the mark of a conflict.
  /// - Precondition: `role` takes part in the session.
  init(
    lines role: Role, text: DisplayText, of changes: SessionChanges, lineEndings: [LineEnding],
    document: ResultDocument?, ignoredDifferences: IgnoredDifferences, showsIgnoredPlaces: Bool,
    baseIsShown: Bool
  ) {
    let session = changes.session
    let lineCount = session.rowLayout.lineCount(in: role)
    let blocks = Self.blocks(
      source: role, of: changes, document: document, baseIsShown: baseIsShown, alignsLines: false)
    guard lineCount > 0 else {
      self.init(text: "", lineNumbers: [-1], blocks: blocks, marksBlocksWithoutRows: true)
      return
    }
    let places =
      showsIgnoredPlaces
      ? Self.places(of: ignoredDifferences, in: role, of: session) {
        text.utf16Range(ofRow: $0).lowerBound
      } : []
    self.init(
      text: text.string, lineNumbers: (0..<Int32(lineCount)).map(\.self), blocks: blocks,
      ignoredDifferenceRows: ignoredDifferences.lines(in: role), ignoredDifferencePlaces: places,
      lineEndings: lineEndings, marksBlocksWithoutRows: true)
  }

  /// The places where the lines of `role` differ in a way that the comparison ignores, as
  /// ranges of the pane's text, whose line starts at the offset `lineStart` gives.
  private static func places(
    of ignoredDifferences: IgnoredDifferences, in role: Role, of session: Session,
    lineStart: (Int) -> Int
  ) -> [Range<Int>] {
    do {
      return try ignoredDifferences.places(in: role, of: session).map { place in
        let start = lineStart(place.line)
        return start + place.range.lowerBound..<start + place.range.upperBound
      }
    } catch {
      // Without the places, the rings in the gutter still mark the lines.
      logger.error("No places of ignored changes: \(error, privacy: .public)")
      return []
    }
  }

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// The blocks of the pane of `role`, one of the inputs of the session: each changed block,
  /// tinted as ``SessionChanges/style(of:in:conflictIsOpen:comparesSides:)`` says, marked as the
  /// side changed it and as far as its conflict is decided in `document`.
  ///
  /// - Parameters:
  ///   - baseIsShown: Whether the pane of the base is in view; while it is hidden, the panes
  ///     compare A with B and B carries the mark of a conflict.
  ///   - alignsLines: Whether the pane shows the rows of the grid, or else the lines of its file
  ///     without filler rows.
  static func blocks(
    source role: Role, of changes: SessionChanges, document: ResultDocument?,
    baseIsShown: Bool, alignsLines: Bool
  ) -> [PaneBlock] {
    let layout = changes.session.rowLayout
    let conflictMarkRole = changes.conflictMarkRole(baseIsShown: baseIsShown)
    let comparesSides = changes.comparesSides(baseIsShown: baseIsShown)
    return changes.blocks.map { block in
      let isOpen = document?.segment(for: block).state == .open
      let carriesConflictMark = block.kind == .conflict && role == conflictMarkRole
      return PaneBlock(
        rows: alignsLines ? layout.rows(of: block) : block.lines(in: role),
        style: changes.style(
          of: role, in: block, conflictIsOpen: isOpen, comparesSides: comparesSides),
        marker: changes.marker(of: role, in: block),
        conflict: carriesConflictMark ? (isOpen ? .open : .resolved) : nil,
        move: changes.moveMark(of: role, in: block))
    }
  }

  /// How each of the `lineCount` lines of `file` ends.
  ///
  /// The lines are those of the comparison: they end at LF, or at CR in a file whose lines all
  /// end in CR. Where the file splits into another number of lines, as a comparison mode that
  /// also ends lines at a lone CR does, each line counts as ending like most lines of the file.
  static func lineEndings(of file: SourceFile, lineCount: Int) -> [LineEnding] {
    // Line endings are ASCII, so the UTF-8 of the text finds them without a copy of it.
    let text = file.text?.utf8 ?? "".utf8
    let separator = file.lineEndings == .cr ? Self.carriageReturn : Self.lineFeed
    var endings: [LineEnding] = []
    endings.reserveCapacity(lineCount)
    var previous: UInt8?
    for unit in text {
      defer { previous = unit }
      guard unit == separator else { continue }
      if separator == Self.carriageReturn {
        endings.append(.carriageReturn)
      } else {
        endings.append(previous == Self.carriageReturn ? .carriageReturnLineFeed : .lineFeed)
      }
    }
    if previous != separator && previous != nil {
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

  private static let lineFeed = UInt8(ascii: "\n")
  private static let carriageReturn = UInt8(ascii: "\r")
}
