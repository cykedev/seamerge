/// One step on the undo stack of a result: the replacements carried out with the texts they
/// replaced, and the changes of the segments, so that undoing restores text and segments together.
///
/// ``ResultDocument/apply(_:replacedTexts:)`` returns a step for every plan. Applying the step's
/// ``undoPlan`` takes it back and returns the step that redoes it.
public struct UndoStep: Sendable {
  /// A replacement as it was carried out.
  struct Replacement: Sendable {
    /// The replaced range in the text before the replacement, in UTF-16 code units.
    let range: Range<Int>

    /// The text that the range held.
    let replacedText: String

    /// The text that replaced it.
    let text: String
  }

  /// The replacements, in the order they were carried out.
  let replacements: [Replacement]

  /// The changes of the segment table, in the order they were made.
  let tableChanges: [TableChange]

  /// Whether the step records typing.
  ///
  /// Typing that continues without a command, a move of the cursor or a pause in between belongs
  /// to one step; the result pane decides that and joins the steps with ``coalesced(with:)``.
  public let isTyping: Bool

  /// The plan that takes the step back.
  public var undoPlan: EditPlan {
    EditPlan(
      replacements: replacements.reversed().map { replacement in
        TextReplacement(
          range: replacement.range.lowerBound..<replacement.range.lowerBound
            + replacement.text.utf16.count,
          text: replacement.replacedText)
      },
      tableChanges: tableChanges.reversed().map(\.inverse), isTyping: false)
  }

  /// The step that does this one and then `later`, or `nil` unless both record typing.
  public func coalesced(with later: UndoStep) -> UndoStep? {
    guard isTyping, later.isTyping else { return nil }
    return UndoStep(
      replacements: replacements + later.replacements,
      tableChanges: tableChanges + later.tableChanges, isTyping: true)
  }
}
