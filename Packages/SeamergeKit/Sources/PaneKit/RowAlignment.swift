import AppKit

/// Lines up the rows of panes on the same grid, such as the sides of a comparison, while their
/// lines wrap: each row is as high in every pane as in the pane that wraps it most.
///
/// Panes on different grids, such as the result of a merge and its sources, line up only by
/// scrolling (see ``ScrollSync``), and each wraps on its own.
@MainActor
public final class RowAlignment {
  private var panes: [WeakPane] = []

  /// Creates an alignment without panes.
  public init() {}

  /// Lines up the rows of `pane` with those of the panes already added.
  ///
  /// - Precondition: `pane` belongs to no alignment.
  public func add(_ pane: PaneView) {
    precondition(pane.rowAlignment == nil, "A pane lines up its rows in one alignment at most")
    panes.removeAll { $0.pane == nil }
    panes.append(WeakPane(pane: pane))
    pane.rowAlignment = self
    align()
  }

  /// Releases `pane`, whose rows then take the lines of its own text alone.
  public func remove(_ pane: PaneView) {
    guard pane.rowAlignment === self else { return }
    panes.removeAll { $0.pane == nil || $0.pane === pane }
    pane.rowAlignment = nil
    pane.alignRows()
    align()
  }

  /// Gives every pane the rows that wrap in any of them, each with the most lines.
  func align() {
    let aligned = panes.compactMap(\.pane)
    let wrappedRows = aligned.reduce(WrappedRows.none) { rows, pane in
      rows.merged(with: pane.textView.ownWrappedRows)
    }
    for pane in aligned {
      pane.showWrappedRows(wrappedRows)
    }
  }

  private struct WeakPane {
    weak var pane: PaneView?
  }
}
