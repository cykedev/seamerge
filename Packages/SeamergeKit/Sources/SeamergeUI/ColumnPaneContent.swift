import Foundation
import MergeModel
import PaneKit
import os

extension PaneContent {
  /// The content of the pane that shows both files of a comparison in `column`: the lines both
  /// share once, and in each changed block the lines of the first side above those of the second,
  /// each part tinted and marked as the pane of its side tints and marks it.
  ///
  /// The rows number the lines of the column from 0; the gutter shows the lines of both files in
  /// two columns, the left one for the side on the left of the panes side by side.
  ///
  /// - Parameters:
  ///   - changes: The changed blocks of the session, which become the blocks of the content.
  ///   - lineEndings: How each line of each file ends, ``lineEndings(of:lineCount:)``.
  ///   - ignoredDifferences: The lines whose differences the comparison ignores, which get a ring
  ///     in the gutter.
  ///   - showsIgnoredPlaces: Whether the places where those lines differ are highlighted.
  /// - Precondition: `column` lays out the session of `changes`, a comparison, and `lineEndings`
  ///   has the endings of both its files.
  init(
    column: SingleColumnLayout, of changes: SessionChanges, lineEndings: [Role: [LineEnding]],
    ignoredDifferences: IgnoredDifferences, showsIgnoredPlaces: Bool
  ) {
    let session = changes.session
    let firstSide = column.firstSide
    let secondSide = Self.otherSide(of: firstSide)
    guard column.rowCount > 0 else {
      self = .empty
      return
    }
    guard let firstEndings = lineEndings[firstSide], let secondEndings = lineEndings[secondSide]
    else {
      preconditionFailure("The line endings of both files are needed")
    }
    var left: [Int32] = []
    var right: [Int32] = []
    var endings: [LineEnding] = []
    left.reserveCapacity(column.rowCount)
    right.reserveCapacity(column.rowCount)
    endings.reserveCapacity(column.rowCount)
    // Block by block, as the column lays out its rows: the lines both sides share, each in the
    // text of the second side, then the lines of the first side alone, then those of the second.
    for block in session.blocks {
      let (firstLines, secondLines) = (block.lines(in: firstSide), block.lines(in: secondSide))
      let firstPart = column.rows(of: block, showingOnly: firstSide)
      let shared = firstPart.lowerBound - column.rows(of: block).lowerBound
      for offset in 0..<shared {
        left.append(Int32(firstLines.lowerBound + offset))
        right.append(Int32(secondLines.lowerBound + offset))
        endings.append(secondEndings[secondLines.lowerBound + offset])
      }
      for line in firstLines.dropFirst(shared) {
        left.append(Int32(line))
        right.append(-1)
        endings.append(firstEndings[line])
      }
      for line in secondLines.dropFirst(shared) {
        left.append(-1)
        right.append(Int32(line))
        endings.append(secondEndings[line])
      }
    }
    let places =
      showsIgnoredPlaces ? Self.places(of: ignoredDifferences, on: column, of: session) : []
    self.init(
      text: column.displayText.string, lineNumbers: (0..<Int32(column.rowCount)).map(\.self),
      sideLineNumbers: SideLineNumbers(left: left, right: right),
      blocks: Self.blocks(column: column, of: changes),
      ignoredDifferenceRows: ignoredDifferences.rows(on: column), ignoredDifferencePlaces: places,
      lineEndings: endings)
  }

  /// The blocks of the pane of `column`: each changed block, its first part tinted and marked as
  /// the first side changed it and its second part as the second side did.
  ///
  /// A block with lines of one side only has one part; an end of a move is such a block, with
  /// its arrow.
  ///
  /// - Precondition: `column` lays out the session of `changes`, a comparison.
  static func blocks(column: SingleColumnLayout, of changes: SessionChanges) -> [PaneBlock] {
    let firstSide = column.firstSide
    let secondSide = otherSide(of: firstSide)
    return changes.blocks.map { block in
      let first = column.rows(of: block, showingOnly: firstSide)
      let second = column.rows(of: block, showingOnly: secondSide)
      let (upperSide, lower) = first.isEmpty ? (secondSide, nil) : (firstSide, second)
      return PaneBlock(
        rows: column.rows(of: block),
        style: changes.style(of: upperSide, in: block, conflictIsOpen: false),
        marker: changes.marker(of: upperSide, in: block),
        move: changes.moveMark(of: firstSide, in: block)
          ?? changes.moveMark(of: secondSide, in: block),
        lowerPart: lower.flatMap { rows in
          rows.isEmpty
            ? nil
            : PaneBlockPart(
              firstRow: rows.lowerBound,
              style: changes.style(of: secondSide, in: block, conflictIsOpen: false),
              marker: changes.marker(of: secondSide, in: block))
        })
    }
  }

  /// The places where the lines of `column` differ in a way that the comparison ignores.
  private static func places(
    of ignoredDifferences: IgnoredDifferences, on column: SingleColumnLayout, of session: Session
  ) -> [Range<Int>] {
    do {
      return try ignoredDifferences.places(on: column, of: session)
    } catch {
      // Without the places, the rings in the gutter still mark the lines.
      columnLogger.error("No places of ignored changes: \(error, privacy: .public)")
      return []
    }
  }

  private static let columnLogger = Logger(
    subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// The other side of a comparison.
  static func otherSide(of role: Role) -> Role {
    role == .a ? .b : .a
  }
}
