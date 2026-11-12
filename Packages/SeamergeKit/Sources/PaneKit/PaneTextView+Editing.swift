import AppKit

extension PaneTextView {
  /// An edit that the pane expects its text to undergo, with the text it replaces.
  struct Announcement {
    var edit: PaneEdit
    var replacedText: String
    /// Whether the edit comes from the user through the text view, which reports it to the
    /// editing delegate once the text view has finished the change.
    var isTyped: Bool
  }

  /// Asks the editing delegate how to carry out each change that the user makes, before the text
  /// view makes it: every way of editing, typing, input methods and dead keys among them, passes
  /// through here.
  ///
  /// An edit that the delegate answers with itself goes through; one that it answers otherwise is
  /// refused and its answer carried out instead. An edit that would remove or change rows behind
  /// a collapsed run is refused, and the run asked to expand, so that nothing hidden is lost
  /// unseen.
  override func shouldChangeText(
    inRanges affectedRanges: [NSValue], replacementStrings: [String]?
  ) -> Bool {
    guard
      isEditable, let interaction, let replacementStrings,
      replacementStrings.count == affectedRanges.count
    else { return false }
    let edits = zip(affectedRanges, replacementStrings).map { range, text in
      PaneEdit(range: Range(range.rangeValue) ?? 0..<0, text: text)
    }
    let hiddenRuns = Set(edits.flatMap(collapsedRunIndices(touchedBy:)))
    guard hiddenRuns.isEmpty else {
      for run in hiddenRuns.sorted() {
        interaction.askToExpandRun(at: run)
      }
      return false
    }
    if edits.count == 1, let edit = edits.first {
      let plan = interaction.edits(for: edit)
      if plan == [edit] {
        guard
          super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
        else { return false }
        announcements.append(
          Announcement(edit: edit, replacedText: substring(edit.range), isTyped: true))
        return true
      }
      carryOutForTheUser(plan)
      return false
    }
    // Several selections, or text dragged within the view: each edit on its own, from the last to
    // the first, so that the ranges of those still to come stay where they are. The delegate
    // takes over each answer before it is asked the next; the reports follow each other within
    // the one event of the action, which an undo manager that groups by event makes one step.
    for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
      carryOutForTheUser(interaction.edits(for: edit))
    }
    return false
  }

  /// Reports the edits that the user's change carried out, once the text view has finished it.
  override func didChangeText() {
    super.didChangeText()
    let carriedOut = completedEdits
    completedEdits.removeAll()
    // An edit that the text view announced but did not make is not expected any longer.
    announcements.removeAll()
    guard !carriedOut.isEmpty else { return }
    interaction?.didCarryOut(carriedOut.map(\.edit), replacing: carriedOut.map(\.replacedText))
  }

  /// Carries out `edits` in order, each in the text that the edits before it left, and returns
  /// the text that each of them replaced.
  ///
  /// - Precondition: Each range lies within the text as the edits before it left it.
  @discardableResult
  func carryOut(_ edits: [PaneEdit]) -> [String] {
    guard let textStorage else { return [] }
    // An edit of the user that the text view announced but has not made by now never comes.
    announcements.removeAll { $0.isTyped }
    let attributes = textAttributes
    return edits.map { edit in
      precondition(
        edit.range.lowerBound >= 0 && edit.range.upperBound <= textStorage.length,
        "The edited range \(edit.range) is outside the text of length \(textStorage.length)")
      let replacedText = substring(edit.range)
      announcements.append(
        Announcement(edit: edit, replacedText: replacedText, isTyped: false))
      textStorage.replaceCharacters(
        in: NSRange(edit.range), with: NSAttributedString(string: edit.text, attributes: attributes)
      )
      return replacedText
    }
  }

  /// Carries out the delegate's answer to an edit of the user in place of the edit, puts the
  /// insertion point after the text of its last edit and reports it.
  private func carryOutForTheUser(_ edits: [PaneEdit]) {
    guard let last = edits.last else { return }
    let replacedTexts = carryOut(edits)
    setSelectedRange(NSRange(location: last.range.lowerBound + last.text.utf16.count, length: 0))
    interaction?.didCarryOut(edits, replacing: replacedTexts)
  }

  /// The text of `range`.
  private func substring(_ range: Range<Int>) -> String {
    (string as NSString).substring(with: NSRange(range))
  }

  /// The indices of the collapsed runs whose rows `edit` would change: those its range reaches
  /// into, or, for an insertion, the run whose hidden text it would go into.
  private func collapsedRunIndices(touchedBy edit: PaneEdit) -> [Int] {
    displayRows.runs.indices.filter { index in
      let rows = displayRows.runs[index].rows
      let hidden =
        grid.offsets(ofRow: rows.lowerBound)
        .lowerBound..<grid.offsets(ofRow: rows.upperBound - 1)
        .upperBound
      guard edit.range.isEmpty else { return edit.range.overlaps(hidden) }
      // At the end of the text, an insertion goes into a run that reaches the last row.
      let offset = edit.range.lowerBound
      return hidden.contains(offset)
        || (rows.upperBound == grid.rowCount && offset == hidden.upperBound)
    }
  }
}

extension PaneTextView: @MainActor NSTextStorageDelegate {
  /// Keeps the rows, blocks and collapsed runs in step with each change of the text,
  /// before TextKit lays out the changed text, and finds changes that nobody announced.
  ///
  /// The edited range that the text storage reports may reach beyond the change, to the whole
  /// paragraph when it fixes attributes along with it; an announced edit within it whose text is
  /// in place counts as the change.
  func textStorage(
    _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
    range editedRange: NSRange, changeInLength delta: Int
  ) {
    guard editedMask.contains(.editedCharacters), !isShowingContent else { return }
    let text = textStorage.string as NSString
    let edited = editedRange.location..<editedRange.location + editedRange.length
    // Announcements before the one that explains the change were not carried out.
    if let index = announcements.firstIndex(where: {
      Self.edit($0.edit, explains: edited, delta: delta, in: text)
    }) {
      let announcement = announcements[index]
      announcements.removeSubrange(...index)
      if announcement.isTyped {
        completedEdits.append(announcement)
      }
      takeOver(announcement.edit, in: text)
    } else {
      announcements.removeAll()
      let edit = PaneEdit(
        range: edited.lowerBound..<edited.upperBound - delta,
        text: text.substring(with: editedRange))
      takeOver(edit, in: text)
      interaction?.textDidChangeWithoutAnnouncing(edit)
    }
  }

  /// Whether `edit` is the change of the text, now `text`, that the text storage reports as
  /// `edited` with `delta`: its length changes by as much, its new text lies within `edited`, and
  /// is in place.
  private static func edit(
    _ edit: PaneEdit, explains edited: Range<Int>, delta: Int, in text: NSString
  ) -> Bool {
    let length = edit.text.utf16.count
    guard
      length - edit.range.count == delta, edited.lowerBound <= edit.range.lowerBound,
      edit.range.lowerBound + length <= edited.upperBound
    else { return false }
    return text.compare(
      edit.text, options: .literal,
      range: NSRange(location: edit.range.lowerBound, length: length)) == .orderedSame
  }

  /// Takes over `edit` of the text, now `text`, into the rows and what stands on them.
  private func takeOver(_ edit: PaneEdit, in text: NSString) {
    let change = grid.replace(edit.range, withLength: edit.text.utf16.count, in: text)
    takeOver(change, text: text as String)
  }
}
