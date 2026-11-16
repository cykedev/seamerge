import MergeModel
import PaneKit
import os

/// Supplies a pane above the result with the changed runs within the lines of its blocks, as
/// the merge model finds them: in the text of the grid, in the text without filler rows, or in
/// the text of a single column.
@MainActor
final class BlockHighlights: PaneHighlightProvider {
  /// The rows a pane shows, in whose text the runs lie.
  enum Rows {
    /// The rows of the grid of the input of a role.
    case grid(Role)

    /// The lines of the file of the input of a role, without filler rows.
    case lines(Role)

    /// Both files of a comparison in a single column.
    case column(SingleColumnLayout)
  }

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  private let changes: SessionChanges
  private let rows: Rows

  /// Creates the provider for a pane that shows `rows`.
  init(changes: SessionChanges, rows: Rows) {
    self.changes = changes
    self.rows = rows
  }

  func highlights(forBlock block: Int) -> [Range<Int>] {
    let block = changes.blocks[block]
    do {
      let highlights = try changes.session.inlineHighlights(for: block)
      switch rows {
      case .grid(let role):
        return highlights.ranges(in: role)
      case .lines(let role):
        // Within a block, a side's lines come first, before its filler rows, each of which
        // holds nothing but its line feed; so the text without them is shorter by one code unit
        // for each filler row before the block.
        let fillerRows =
          changes.session.rowLayout.rows(of: block).lowerBound - block.lines(in: role).lowerBound
        return highlights.ranges(in: role).map {
          $0.lowerBound - fillerRows..<$0.upperBound - fillerRows
        }
      case .column(let column):
        // Each side's runs lie on rows of its own, the first side's above the second's.
        let firstSide = column.firstSide
        return highlights.ranges(in: firstSide, on: column)
          + highlights.ranges(in: PaneContent.otherSide(of: firstSide), on: column)
      }
    } catch {
      // Without highlights the rows still show the change; the runs within them are a help.
      Self.logger.error(
        "No highlights for block \(block.id, privacy: .public): \(error, privacy: .public)")
      return []
    }
  }
}
