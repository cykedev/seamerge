import MergeModel
import PaneKit

/// The marks of the overview bars: the bar beside the panes side by side, on their row grid, the
/// bar beside the result, on its rows, and the bar beside a single column, on its rows.
///
/// A change of the side on the left takes the leading part of a bar and a change of the side on
/// the right the trailing part, so that the place says which side changed even without color; a
/// change both made takes both. A conflict
/// takes the full width, red while it is open and in the color of its source once it is decided,
/// so that it stays visible where conflicts were.
enum OverviewMarks {
  /// The marks of the bar beside the panes side by side, whose sides stand as `arrangement`
  /// places them; `document` is the result of a merge, or `nil` for a comparison.
  static func sources(
    of changes: SessionChanges, document: ResultDocument?, arrangement: PaneArrangement
  ) -> [OverviewMark] {
    let layout = changes.session.rowLayout
    let sides = [
      (arrangement.leadingRole, OverviewMark.Placement.leading),
      (arrangement.trailingRole, .trailing),
    ]
    var marks: [OverviewMark] = []
    for (index, block) in changes.blocks.enumerated() {
      let rows = layout.rows(of: block)
      if block.kind == .conflict, let document {
        let segment = document.segment(for: block)
        marks.append(
          conflictMark(
            rows: rows, segment: segment, block: index,
            line: firstLine(of: block, in: changes.hasBase ? .base : .b)))
        continue
      }
      for (role, placement) in sides where SessionChanges.changers(of: block).contains(role) {
        marks.append(
          OverviewMark(
            rows: rows, style: .tinted(role.colorRole), placement: placement, block: index,
            accessibilityLabel: changeLabel(of: role, line: firstLine(of: block, in: role))))
      }
    }
    return marks
  }

  /// The marks of the bar beside a single column, on its rows: the marks of the two parts of a
  /// block one below the other, each on the side of the bar where the panes side by side put
  /// its side, so that the place still says which side changed without color.
  static func column(of changes: SessionChanges, column: SingleColumnLayout) -> [OverviewMark] {
    let sides = [
      (column.firstSide, OverviewMark.Placement.leading),
      (PaneContent.otherSide(of: column.firstSide), .trailing),
    ]
    var marks: [OverviewMark] = []
    for (index, block) in changes.blocks.enumerated() {
      for (role, placement) in sides {
        let rows = column.rows(of: block, showingOnly: role)
        let style = changes.style(of: role, in: block, conflictIsOpen: false)
        guard !rows.isEmpty, style != .unchanged else { continue }
        marks.append(
          OverviewMark(
            rows: rows, style: style, placement: placement, block: index,
            accessibilityLabel: changeLabel(of: role, line: firstLine(of: block, in: role))))
      }
    }
    return marks
  }

  /// The marks of the bar beside the result, whose blocks are those of `result`.
  static func result(
    of changes: SessionChanges, document: ResultDocument, result: PaneContent
  ) -> [OverviewMark] {
    var marks: [OverviewMark] = []
    for (index, (block, paneBlock)) in zip(changes.blocks, result.blocks).enumerated() {
      let segment = document.segment(for: block)
      let line = paneBlock.rows.lowerBound + 1
      if block.kind == .conflict {
        marks.append(conflictMark(rows: paneBlock.rows, segment: segment, block: index, line: line))
        continue
      }
      let label = String(
        localized: "\(sourceDescription(of: segment)), line \(line)", bundle: .module,
        comment: "VoiceOver: a mark in the overview bar of the result, such as From A, line 12.")
      let style = ResultPaneContent.style(of: segment)
      for (role, placement) in [(Role.a, OverviewMark.Placement.leading), (.b, .trailing)]
      where SessionChanges.changers(of: block).contains(role) {
        marks.append(
          OverviewMark(
            rows: paneBlock.rows, style: style, placement: placement, block: index,
            accessibilityLabel: label))
      }
    }
    return marks
  }

  /// What VoiceOver calls the mark of a change of `role` that starts at `line`, counted from 1.
  private static func changeLabel(of role: Role, line: Int) -> String {
    String(
      localized: "Change in \(role.letter), line \(line)", bundle: .module,
      comment: "VoiceOver: a mark in the overview bar, such as Change in A, line 12.")
  }

  /// The mark of a conflict: red while open, in the color of its source once decided.
  private static func conflictMark(
    rows: Range<Int>, segment: Segment, block: Int, line: Int
  ) -> OverviewMark {
    let isOpen = segment.state == .open
    let label =
      isOpen
      ? String(
        localized: "Open conflict, line \(line)", bundle: .module,
        comment: "VoiceOver: the mark of an open conflict in the overview bar.")
      : String(
        localized: "Resolved conflict, line \(line)", bundle: .module,
        comment: "VoiceOver: the mark of a decided conflict in the overview bar.")
    return OverviewMark(
      rows: rows, style: ResultPaneContent.style(of: segment), placement: .fullWidth,
      block: block, accessibilityLabel: label)
  }

  /// Where the text of a decided segment comes from, in words.
  private static func sourceDescription(of segment: Segment) -> String {
    if segment.state == .edited {
      return String(
        localized: "Edited by hand", bundle: .module,
        comment: "VoiceOver: a part of the result that the user typed.")
    }
    let sides = segment.sources.filter { $0 != .base }
    switch (sides.count, segment.sources.isEmpty) {
    case (_, true):
      return String(
        localized: "Nothing taken", bundle: .module,
        comment: "VoiceOver: a part of the result that takes no lines.")
    case (0, _):
      return String(
        localized: "From the base", bundle: .module,
        comment: "VoiceOver: a part of the result taken from the common ancestor.")
    case (1, _):
      return String(
        localized: "From \(sides[0].letter)", bundle: .module,
        comment: "VoiceOver: a part of the result taken from one side, such as From A.")
    default:
      return String(
        localized: "From \(sides[0].letter) and \(sides[1].letter)", bundle: .module,
        comment: "VoiceOver: a part of the result taken from both sides, such as From A and B.")
    }
  }

  /// The number of the first line of `block` in `role`, counted from 1; for a block without
  /// lines there, the line it lies before.
  private static func firstLine(of block: Block, in role: Role) -> Int {
    block.lines(in: role).lowerBound + 1
  }
}
