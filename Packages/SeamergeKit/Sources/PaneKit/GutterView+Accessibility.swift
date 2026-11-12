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
  /// ignored differences and marks of removed text, each named with the line it stands at.
  override func accessibilityChildren() -> [Any]? {
    let rows = visibleRows
    var children: [NSAccessibilityElement] = []
    for row in rows {
      let rowRect = rect(ofRow: row)
      var names: [String] = []
      if let blockIndex = content.blockIndex(atRow: row),
        content.blocks[blockIndex].rows.lowerBound == row
      {
        let block = content.blocks[blockIndex]
        if let conflict = block.conflict { names.append(Self.name(of: conflict)) }
        if let marker = block.marker { names.append(Self.name(of: marker)) }
      }
      if names.isEmpty && content.ignoredDifferenceRows.contains(row) {
        names.append(
          String(
            localized: "Ignored difference", bundle: .module,
            comment: "VoiceOver: a line that differs only in what the comparison ignores."))
      }
      for (index, name) in names.reversed().enumerated() {
        children.append(element(named: name, atRow: row, frame: markerSlot(index, in: rowRect)))
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
          atRow: row, frame: rect(ofRow: row)))
    }
    return children
  }

  /// The button that collapses the expanded run at `index` again, found beside the run's first
  /// row whether or not the pointer shows its sign.
  private func collapseElement(ofRun index: Int) -> NSAccessibilityElement {
    let run = expandedRuns[index]
    let element = CollapseRunElement { [weak self] in self?.interaction?.askToCollapse(run) }
    element.setAccessibilityRole(.button)
    element.setAccessibilityLabel(
      String(
        localized: "Collapse \(run.rows.count) Unchanged Lines", bundle: .module,
        comment: "VoiceOver: the sign beside an expanded run of unchanged lines that hides them."))
    element.setAccessibilityValue(placeDescription(ofRow: run.rows.lowerBound))
    element.setAccessibilityParent(self)
    element.setAccessibilityFrameInParentSpace(collapseSignRect(ofRun: index))
    return element
  }

  private func element(named name: String, atRow row: Int, frame: CGRect) -> NSAccessibilityElement
  {
    let element = NSAccessibilityElement()
    element.setAccessibilityRole(.image)
    element.setAccessibilityLabel(name)
    element.setAccessibilityValue(placeDescription(ofRow: row))
    element.setAccessibilityParent(self)
    element.setAccessibilityFrameInParentSpace(frame)
    return element
  }

  /// Where `row` is, in words: its line, or for a filler row the line it follows.
  private func placeDescription(ofRow row: Int) -> String {
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

  private static func name(of marker: Marker) -> String {
    switch marker {
    case .added:
      String(localized: "Added", bundle: .module, comment: "VoiceOver: the side added lines.")
    case .changed:
      String(localized: "Changed", bundle: .module, comment: "VoiceOver: the side changed lines.")
    case .removed:
      String(localized: "Removed", bundle: .module, comment: "VoiceOver: the side removed lines.")
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
