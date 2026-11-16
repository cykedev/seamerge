import AppKit
import PaneKit

/// The search over the panes of the window: which rows it goes through in which order, and the
/// strokes of its matches in the overview bars.
extension SessionPresentation {
  /// The panes that the search goes through, in reading order: in a merge A, the base and B,
  /// then the result; in a comparison the left pane, then the right one, or the single column
  /// alone while it shows.
  ///
  /// A hidden base is left out, and a maximized result is searched alone.
  var searchedPanes: [PaneView] {
    if columnLayout != nil, let columnPane = layout.columnPane {
      return [columnPane]
    }
    let sources =
      layout.maximizesResult
      ? [] : layout.sourcePanes.filter { $0.role != .base || layout.showsBase }.map(\.pane)
    return sources + [layout.resultPane].compactMap(\.self)
  }

  /// The rows that the search goes through, in the order of Find Next: block by block, each
  /// stretch of unchanged rows before a changed block counting as a block of its own, and within
  /// each the panes in reading order.
  ///
  /// The changed blocks have the same numbers in every pane; the rows of each pane between them
  /// are its unchanged rows. Should a pane give a block rows before those of the block ahead of
  /// it, the search goes through each row once, where it comes first.
  var searchSections: [PaneSearch.Section] {
    let panes = searchedPanes
    let blockCount = panes.map(\.content.blocks.count).min() ?? 0
    var starts = panes.map { _ in 0 }
    var sections: [PaneSearch.Section] = []
    for block in 0...blockCount {
      for stretch in [Stretch.before(block), .of(block)] {
        for (index, pane) in panes.enumerated() {
          let rows = stretch.rows(in: pane, from: starts[index], blockCount: blockCount)
          starts[index] = rows.upperBound
          if !rows.isEmpty {
            sections.append(PaneSearch.Section(pane: pane, rows: rows))
          }
        }
      }
    }
    return sections
  }

  /// Gives the search the sections of what the panes show now, unless it has them already.
  func updateSearchSections() {
    let sections = searchSections
    let isSame =
      sections.count == search.sections.count
      && zip(sections, search.sections).allSatisfy { $0.pane === $1.pane && $0.rows == $1.rows }
    guard !isSame else { return }
    search.sections = sections
  }

  /// Marks the rows of the matches of the search in the overview bars: those of the panes side
  /// by side on the rows of the grid in their bar, those of the result and of the single column
  /// each in its own.
  func showSearchMatches() {
    var sourceRows = IndexSet()
    var resultRows = IndexSet()
    var columnRows = IndexSet()
    for match in search.matches {
      let row = match.pane.row(containingOffset: match.range.lowerBound)
      if match.pane === layout.resultPane {
        resultRows.insert(row)
      } else if match.pane === layout.columnPane {
        columnRows.insert(row)
      } else {
        sourceRows.insert(gridRow(ofRow: row, in: match.pane))
      }
    }
    sourcesOverviewBar.matchRows = sourceRows
    resultOverviewBar?.matchRows = resultRows
    columnOverviewBar?.matchRows = columnRows
  }

  /// The changed block that the match of the search lies in, if any.
  func block(of match: PaneSearch.Match) -> Int? {
    let row = match.pane.row(containingOffset: match.range.lowerBound)
    return match.pane.content.blocks.firstIndex { $0.rows.contains(row) }
  }
}

extension SessionPresentation: PaneSearchDelegate {
  /// Makes the block of the match current, if it lies in a changed block; the pane of the match
  /// has scrolled to it, the coupled panes along with it, and a collapsed run around it has
  /// expanded.
  func paneSearch(_ search: PaneSearch, didReveal match: PaneSearch.Match) {
    guard let block = block(of: match) else { return }
    setCurrentBlock(block)
  }

  /// Marks the matches in the overview bars and tells VoiceOver how many there are once the
  /// finder has searched, while the user works in the find bar; matches that go because the
  /// text changed are no result of a search.
  func paneSearchDidChangeMatches(_ search: PaneSearch) {
    showSearchMatches()
    guard search.matchesAreCurrent, let responder = layout.view.window?.firstResponder,
      let view = (responder as? NSText)?.delegate as? NSView ?? responder as? NSView,
      view.isDescendant(of: search.findBar)
    else { return }
    var panes: [PaneView] = []
    for match in search.matches where !panes.contains(where: { $0 === match.pane }) {
      panes.append(match.pane)
    }
    announce(Self.matchesAnnouncement(matchCount: search.matches.count, paneCount: panes.count))
  }

  /// Tells the delegate, which keeps the steps of undo.
  func paneSearchWillReplace(_ search: PaneSearch) {
    delegate?.presentationWillReplaceMatches(self)
  }

  /// Tells the delegate, which keeps the steps of undo.
  func paneSearch(_ search: PaneSearch, didReplaceAll replacesAll: Bool) {
    delegate?.presentation(self, didReplaceAllMatches: replacesAll)
  }

  /// What VoiceOver says once the search has found `matchCount` matches in `paneCount` panes,
  /// such as 12 matches in 3 panes.
  static func matchesAnnouncement(matchCount: Int, paneCount: Int) -> String {
    guard matchCount > 0 else {
      return String(
        localized: "No matches", bundle: .module,
        comment: "VoiceOver: the search found nothing in the panes.")
    }
    return String(
      localized: "\(matchCount) matches in \(paneCount) panes", bundle: .module,
      comment: "VoiceOver: how often the search found its text and in how many panes.")
  }
}

/// A stretch of rows that the search goes through as one block: the unchanged rows before a
/// changed block, or the rows of the block itself.
private enum Stretch {
  /// The unchanged rows before the changed block, or after the last block if it is the count of
  /// the blocks.
  case before(Int)

  /// The rows of the changed block.
  case of(Int)

  /// The rows of the stretch in `pane`, from `start` on, where the stretch before it ended.
  func rows(in pane: PaneView, from start: Int, blockCount: Int) -> Range<Int> {
    let blocks = pane.content.blocks
    let end: Int
    switch self {
    case .before(let block):
      end = block < blockCount ? blocks[block].rows.lowerBound : pane.content.lineNumbers.count
    case .of(let block):
      guard block < blockCount else { return start..<start }
      end = blocks[block].rows.upperBound
    }
    return start..<max(start, end)
  }
}
