/// A change of the result text: a range of the text and the text that replaces it.
public struct TextReplacement: Sendable, Hashable {
  /// The replaced range, in UTF-16 code units.
  public var range: Range<Int>

  /// The text that replaces the range.
  public var text: String

  /// Creates a replacement of `range` by `text`.
  public init(range: Range<Int>, text: String) {
    self.range = range
    self.text = text
  }
}

/// What the result pane does to carry out a text edit or a command, and how the segments change.
///
/// The pane carries out the replacements in order, each in the text the previous ones left, and
/// then hands the plan and the replaced texts to ``ResultDocument/apply(_:replacedTexts:)``.
public struct EditPlan: Sendable {
  /// The replacements to carry out, in order; each range refers to the text as the replacements
  /// before it left it.
  ///
  /// For a text edit that needs no adjustment, this is the edit itself.
  public let replacements: [TextReplacement]

  /// The changes of the segment table, in order.
  let tableChanges: [TableChange]

  /// Whether the plan carries out typing, which an undo step may join with the typing after it.
  let isTyping: Bool

  /// A plan that changes nothing.
  static let empty = EditPlan(replacements: [], tableChanges: [], isTyping: false)

  /// Whether the plan changes neither the text nor the segments.
  ///
  /// The pane refuses a text edit whose plan is empty.
  public var isEmpty: Bool { replacements.isEmpty && tableChanges.isEmpty }
}

/// A change of the segment table of a result document.
enum TableChange: Sendable {
  /// The segment at `index` changes from `before` to `after`.
  case segment(index: Int, before: Segment, after: Segment)

  /// The whole document changes, because the session was compared anew.
  indirect case document(before: ResultDocument, after: ResultDocument)

  /// The change that takes this one back.
  var inverse: TableChange {
    switch self {
    case .segment(let index, let before, let after):
      .segment(index: index, before: after, after: before)
    case .document(let before, let after):
      .document(before: after, after: before)
    }
  }
}
