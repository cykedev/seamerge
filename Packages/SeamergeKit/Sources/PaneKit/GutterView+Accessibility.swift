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
    for row in removalRows(rows) {
      children.append(
        element(
          named: String(
            localized: "Removed text", bundle: .module,
            comment: "VoiceOver: the mark where a side removed text within a line."),
          atRow: row, frame: rect(ofRow: row)))
    }
    return children
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
