import MergeModel
import PaneKit
import os

/// Supplies a pane above the result with the changed runs within the lines of its blocks, as
/// the merge model finds them, in the text of the grid or in the text without filler rows.
@MainActor
final class BlockHighlights: PaneHighlightProvider {
  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  private let changes: SessionChanges
  private let role: Role
  private let alignsLines: Bool

  /// Creates the provider for the pane of `role`, which shows the rows of the grid if
  /// `alignsLines`, or else the lines of its file without filler rows.
  init(changes: SessionChanges, role: Role, alignsLines: Bool) {
    self.changes = changes
    self.role = role
    self.alignsLines = alignsLines
  }

  func highlights(forBlock block: Int) -> [Range<Int>] {
    let block = changes.blocks[block]
    do {
      let ranges = try changes.session.inlineHighlights(for: block).ranges(in: role)
      guard !alignsLines else { return ranges }
      // Within a block, a side's lines come first, before its filler rows, each of which holds
      // nothing but its line feed; so the text without them is shorter by one code unit for
      // each filler row before the block.
      let fillerRows =
        changes.session.rowLayout.rows(of: block).lowerBound - block.lines(in: role).lowerBound
      return ranges.map { $0.lowerBound - fillerRows..<$0.upperBound - fillerRows }
    } catch {
      // Without highlights the rows still show the change; the runs within them are a help.
      Self.logger.error(
        "No highlights for block \(block.id, privacy: .public): \(error, privacy: .public)")
      return []
    }
  }
}
