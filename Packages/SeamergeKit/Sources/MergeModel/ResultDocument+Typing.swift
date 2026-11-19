import TextBasics

extension ResultDocument {
  /// The plan for an edit of the result text, attributed to the segments it touches.
  ///
  /// The attribution depends on the segments and the edit alone:
  ///
  /// - An edit within one segment changes its length.
  /// - An insertion on a boundary belongs to the segment with text that starts there and is not
  ///   a preview, which is the line being typed on. If there is none, it belongs to the segment
  ///   with text that ends there and is not a preview, as at the end of the text.
  /// - Only if neither exists does an empty segment take the insertion, as after selecting and
  ///   deleting everything: the first segment without a preview that starts there, otherwise the
  ///   nearest one before, at its end, otherwise the nearest one after, at its start. The same
  ///   holds for an insertion within a preview, which cannot take text.
  /// - An edit across several segments gives the replacement text to the first, which keeps its
  ///   start; the last keeps its end, and those in between become empty.
  /// - A preview within an edited range stays; the edit is carried out around it. Text that
  ///   replaces a range within previews alone is inserted as at the start of the range.
  ///
  /// Every segment whose text changes becomes ``Segment/State/edited``. The plan is empty only if
  /// the edit changes nothing outside previews or no segment is free of a preview.
  ///
  /// - Precondition: The range lies within the text.
  public func plan(for edit: TextReplacement) -> EditPlan {
    let starts = segmentStarts()
    precondition(
      edit.range.lowerBound >= 0 && edit.range.upperBound <= starts[starts.count - 1],
      "The edited range \(edit.range) is outside the text")
    if edit.range.isEmpty {
      return planInserting(edit.text, at: edit.range.lowerBound, starts: starts)
    }

    // The parts of the edited range outside previews, joined where they touch; the replacement
    // text goes to the start of the first part.
    var parts: [Range<Int>] = []
    var lengthChanges: [Int: Int] = [:]
    var index = lastSegment(startingAtOrBefore: edit.range.lowerBound, starts: starts)
    while index < segments.count && starts[index] < edit.range.upperBound {
      let overlap =
        max(starts[index], edit.range.lowerBound)..<min(starts[index + 1], edit.range.upperBound)
      if !overlap.isEmpty && segments[index].state != .open {
        lengthChanges[index] = -overlap.count
        if let last = parts.last, last.upperBound == overlap.lowerBound {
          parts[parts.count - 1] = last.lowerBound..<overlap.upperBound
        } else {
          parts.append(overlap)
        }
      }
      index += 1
    }
    guard let owner = lengthChanges.keys.min() else {
      return planInserting(edit.text, at: edit.range.lowerBound, starts: starts)
    }
    lengthChanges[owner, default: 0] += edit.text.utf16.count
    // From the last part to the first, so that each replacement leaves the ranges of those still
    // to come as they were.
    let replacements = parts.indices.reversed().map { part in
      TextReplacement(range: parts[part], text: part == 0 ? edit.text : "")
    }
    return typingPlan(replacements: replacements, lengthChanges: lengthChanges)
  }

  /// The plan that inserts `text` at `offset`, or where the segment that takes it allows.
  private func planInserting(_ text: String, at offset: Int, starts: [Int]) -> EditPlan {
    guard !text.isEmpty, let point = insertionPoint(at: offset, starts: starts) else {
      return .empty
    }
    return typingPlan(
      replacements: [TextReplacement(range: point.offset..<point.offset, text: text)],
      lengthChanges: [point.segment: text.utf16.count])
  }

  /// The segment that takes an insertion at `offset` and where in the text the insertion goes,
  /// or `nil` if every segment is a preview.
  private func insertionPoint(at offset: Int, starts: [Int]) -> (segment: Int, offset: Int)? {
    func takesText(_ index: Int) -> Bool { segments[index].state != .open }
    func hasTextAndTakesText(_ index: Int) -> Bool {
      segments[index].length > 0 && takesText(index)
    }
    guard !segments.isEmpty else { return nil }
    // An empty segment starts where the next one does, so the last segment that starts at or
    // before the offset has text and contains the offset or starts at it, unless the offset is
    // the end of the text.
    let following = lastSegment(startingAtOrBefore: offset, starts: starts)
    if offset < starts[following + 1] && hasTextAndTakesText(following) {
      return (following, offset)
    }
    // Likewise, the segment that holds the character before the offset contains the offset or
    // ends at it.
    if offset > 0 {
      let preceding = lastSegment(startingAtOrBefore: offset - 1, starts: starts)
      if starts[preceding + 1] == offset && hasTextAndTakesText(preceding) {
        return (preceding, offset)
      }
    }
    if let index = segments.indices.first(where: { starts[$0] == offset && takesText($0) }) {
      return (index, offset)
    }
    if let index = segments.indices.last(where: { starts[$0 + 1] <= offset && takesText($0) }) {
      return (index, starts[index + 1])
    }
    if let index = segments.indices.first(where: { starts[$0] >= offset && takesText($0) }) {
      return (index, starts[index])
    }
    return nil
  }

  /// The last segment that starts at or before `offset`.
  ///
  /// - Precondition: There is at least one segment, and `offset` is not negative.
  private func lastSegment(startingAtOrBefore offset: Int, starts: [Int]) -> Int {
    segments.indices.lastIndex(holding: { starts[$0] <= offset })
  }

  /// A typing plan that carries out `replacements` and changes the length of segments by
  /// `lengthChanges`, making each of them edited.
  private func typingPlan(
    replacements: [TextReplacement], lengthChanges: [Int: Int]
  ) -> EditPlan {
    let tableChanges = lengthChanges.keys.sorted().map { index in
      var after = segments[index]
      after.length += lengthChanges[index, default: 0]
      after.state = .edited
      return TableChange.segment(index: index, before: segments[index], after: after)
    }
    return EditPlan(replacements: replacements, tableChanges: tableChanges, isTyping: true)
  }
}
