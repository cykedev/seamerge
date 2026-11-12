import MergeModel
import PaneKit
import os

/// Supplies a pane above the result with the changed runs within the lines of its blocks, as
/// the merge model finds them.
@MainActor
final class BlockHighlights: PaneHighlightProvider {
  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  private let changes: SessionChanges
  private let role: Role

  /// Creates the provider for the pane of `role`.
  init(changes: SessionChanges, role: Role) {
    self.changes = changes
    self.role = role
  }

  func highlights(forBlock block: Int) -> [Range<Int>] {
    do {
      return try changes.session.inlineHighlights(for: changes.blocks[block]).ranges(in: role)
    } catch {
      // Without highlights the rows still show the change; the runs within them are a help.
      Self.logger.error(
        "No highlights for block \(block, privacy: .public): \(error, privacy: .public)")
      return []
    }
  }
}
