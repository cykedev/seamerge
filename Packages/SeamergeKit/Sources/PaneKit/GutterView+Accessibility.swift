import AppKit

extension GutterView {
  override func isAccessibilityElement() -> Bool {
    true
  }

  override func accessibilityRole() -> NSAccessibility.Role? {
    .group
  }

  override func accessibilityLabel() -> String? {
    String(
      localized: "Change markers", bundle: .module, comment: "VoiceOver: the gutter of a pane.")
  }

  /// One element for each mark beside the visible rows: change markers, warning signs, rings of
  /// ignored differences and marks of removed text, each named with the line it stands at; in a
  /// single column also one for each visible row, which names its side and its lines.
  override func accessibilityChildren() -> [Any]? {
    let rows = visibleRows
    var children: [NSAccessibilityElement] = []
    for row in rows {
      let rowRect = rect(ofRow: row)
      for (index, entry) in marks(ofRow: row).enumerated() {
        children.append(
          element(
            named: Self.name(of: entry.mark), help: entry.help, atRow: row,
            frame: markerSlot(index, in: rowRect)))
      }
    }
    for mark in boundaryMarks {
      children.append(
        element(
          named: Self.name(of: mark.mark), help: mark.help,
          place: placeDescription(ofBoundary: mark.boundary), frame: mark.slot))
    }
    if let sides = content.sideLineNumbers {
      for row in rows {
        children.append(rowElement(ofRow: row, sides: sides))
      }
    }
    for index in expandedRuns.indices where rows.contains(expandedRuns[index].rows.lowerBound) {
      children.append(collapseElement(ofRun: index))
    }
    let removals = rows.isEmpty ? [] : removalRows(rows[0]..<rows[rows.count - 1] + 1)
    for row in removals where displayRows.runIndex(containingRow: row) == nil {
      children.append(
        element(
          named: String(
            localized: "Removed text", bundle: .module,
            comment: "VoiceOver: the mark where a side removed text within a line."),
          help: nil, atRow: row, frame: rect(ofRow: row)))
    }
    return children
  }

  /// The element of `row` in a single column, which names its side and its lines: removed, added
  /// or unchanged, beside the columns of line numbers.
  private func rowElement(ofRow row: Int, sides: SideLineNumbers) -> NSAccessibilityElement {
    let element = NSAccessibilityElement()
    element.setAccessibilityRole(.staticText)
    element.setAccessibilityLabel(sides.sideName(ofRow: row))
    element.setAccessibilityValue(sides.placeDescription(ofRow: row))
    element.setAccessibilityParent(self)
    let rowRect = rect(ofRow: row)
    element.setAccessibilityFrameInParentSpace(
      CGRect(
        x: 0, y: rowRect.minY,
        width: bounds.width - CGFloat(markerSlotCount) * Theme.markerSlotWidth,
        height: min(rowRect.height, theme.rowHeight)))
    return element
  }

  /// The button that collapses the expanded run at `index` again, found beside the run's first
  /// row whether or not the pointer shows its sign.
  private func collapseElement(ofRun index: Int) -> NSAccessibilityElement {
    let run = expandedRuns[index]
    let element = CollapseRunElement { [weak self] in self?.interaction?.askToCollapse(run) }
    element.setAccessibilityRole(.button)
    element.setAccessibilityHelp(MarkHelp.collapseRun)
    element.setAccessibilityLabel(
      String(
        localized: "Collapse \(run.rows.count) Unchanged Lines", bundle: .module,
        comment: "VoiceOver: the sign beside an expanded run of unchanged lines that hides them."))
    element.setAccessibilityValue(placeDescription(ofRow: run.rows.lowerBound))
    element.setAccessibilityParent(self)
    element.setAccessibilityFrameInParentSpace(collapseSignRect(ofRun: index))
    return element
  }

  private func element(
    named name: String, help: String?, atRow row: Int, frame: CGRect
  ) -> NSAccessibilityElement {
    element(named: name, help: help, place: placeDescription(ofRow: row), frame: frame)
  }

  private func element(
    named name: String, help: String?, place: String, frame: CGRect
  ) -> NSAccessibilityElement {
    let element = NSAccessibilityElement()
    element.setAccessibilityRole(.image)
    element.setAccessibilityLabel(name)
    element.setAccessibilityHelp(help)
    element.setAccessibilityValue(place)
    element.setAccessibilityParent(self)
    element.setAccessibilityFrameInParentSpace(frame)
    return element
  }

  /// Where `row` is, in words: its line, or for a filler row the line it follows; in a single
  /// column its lines in both files.
  private func placeDescription(ofRow row: Int) -> String {
    if let sides = content.sideLineNumbers {
      return sides.placeDescription(ofRow: row)
    }
    if let line = content.lineNumbers[...row].last(where: { $0 >= 0 }) {
      let number = Int(line) + 1
      return content.lineNumbers[row] >= 0
        ? String(
          localized: "Line \(number)", bundle: .module, comment: "VoiceOver: where a mark is.")
        : String(
          localized: "After line \(number)", bundle: .module,
          comment: "VoiceOver: where a mark beside a filler row is.")
    }
    return String(
      localized: "Before the first line", bundle: .module,
      comment: "VoiceOver: where a mark beside filler rows at the start is.")
  }

  /// Where the boundary before `row` is, in words: after the line above it, or before the first
  /// line.
  private func placeDescription(ofBoundary row: Int) -> String {
    guard
      let line = content.lineNumbers[..<min(row, content.lineNumbers.count)].last(where: {
        $0 >= 0
      })
    else {
      return String(
        localized: "Before the first line", bundle: .module,
        comment: "VoiceOver: where a mark beside filler rows at the start is.")
    }
    return String(
      localized: "After line \(Int(line) + 1)", bundle: .module,
      comment: "VoiceOver: where a mark beside a filler row is.")
  }

  /// What VoiceOver calls `mark`.
  private static func name(of mark: GutterMark) -> String {
    switch mark {
    case .marker(let marker, _): marker.accessibilityName
    case .conflict(let conflict): name(of: conflict)
    case .ignoredDifference:
      String(
        localized: "Ignored difference", bundle: .module,
        comment: "VoiceOver: a line that differs only in what the comparison ignores.")
    }
  }

  private static func name(of conflict: ConflictMarker) -> String {
    switch conflict {
    case .open:
      String(
        localized: "Open conflict", bundle: .module,
        comment: "VoiceOver: a conflict that still needs a decision.")
    case .resolved:
      String(
        localized: "Resolved conflict", bundle: .module,
        comment: "VoiceOver: a conflict that has been decided.")
    }
  }
}

/// The element that VoiceOver finds for the sign that collapses an expanded run, which presses
/// it.
private final class CollapseRunElement: NSAccessibilityElement {
  private let collapse: @MainActor @Sendable () -> Void

  init(collapse: @escaping @MainActor @Sendable () -> Void) {
    self.collapse = collapse
    super.init()
  }

  override func accessibilityPerformPress() -> Bool {
    let collapse = collapse
    // VoiceOver presses elements on the main thread.
    MainActor.assumeIsolated { collapse() }
    return true
  }
}
