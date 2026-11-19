import MergeModel
import PaneKit
import TextBasics

/// The text of a merge result in the two forms it takes: as the file has it, with its own line
/// breaks, and as the result pane shows it, with a line feed for every line break and without the
/// line break that ends the text.
///
/// The document of the result counts offsets in the file's form, the pane in its own; this is the
/// one place that translates between them. Every change of the result passes through
/// ``carryOut(_:)``, which changes the file's form and returns the edit that makes the same change
/// in the pane, so that both forms stay in step.
///
/// Offsets are UTF-16 offsets. A CRLF pair takes two units in the file and one in the pane; every
/// other line break, CR, LF, NEL, U+2028 or U+2029, takes one unit in both.
struct ResultText: Equatable {
  /// The text as the file has it.
  private(set) var string: String

  /// The length of ``string`` in UTF-16 code units.
  private(set) var length: Int

  /// The offset of the carriage return of each CRLF pair in ``string``, in ascending order.
  private var pairs: [Int]

  /// The text `string`, as the file has it.
  init(_ string: String) {
    self.string = string
    let units = Array(string.utf16)
    length = units.count
    pairs = units.indices.dropLast().filter {
      units[$0] == Self.carriageReturn && units[$0 + 1] == Self.lineFeed
    }
  }

  /// The length of the text as the pane shows it.
  var paneLength: Int {
    length - pairs.count - (endsWithLineBreak ? 1 : 0)
  }

  /// Whether the text ends with a line break, which the pane does not show.
  private var endsWithLineBreak: Bool {
    string.utf16.last.map(Self.isLineBreak) ?? false
  }

  /// The offset in the pane's form of `offset` of the file's form.
  ///
  /// The line break that ends the text, and the end after it, lie at the end of the pane's text.
  ///
  /// - Precondition: `offset` lies within the text and not between the units of a CRLF pair.
  func paneOffset(ofFileOffset offset: Int) -> Int {
    min(offset - pairs.partitioningIndex { $0 >= offset }, paneLength)
  }

  /// The offset in the file's form of `offset` of the pane's form.
  ///
  /// The end of the pane's text lies before the line break that ends the text.
  ///
  /// - Precondition: `offset` lies within the pane's text.
  func fileOffset(ofPaneOffset offset: Int) -> Int {
    // The line feed of the pair at `index` lies at `pairs[index] - index` in the pane.
    offset + pairs.indices.partitioningIndex { pairs[$0] - $0 >= offset }
  }

  /// The replacement of the file's form that makes `edit` of the pane's form, which the user is
  /// about to make.
  ///
  /// Each line break of the edit's text becomes the line break of the line the edit starts in,
  /// or of the line before it where that one has none, as the pane takes it for the lines it
  /// breaks; without either, a line feed.
  ///
  /// - Precondition: The edit's range lies within the pane's text, and its text has line feeds
  ///   for line breaks.
  func replacement(for edit: PaneEdit) -> TextReplacement {
    let start = fileOffset(ofPaneOffset: edit.range.lowerBound)
    let range = start..<fileOffset(ofPaneOffset: edit.range.upperBound)
    guard edit.text.utf16.contains(Self.lineFeed) else {
      return TextReplacement(range: range, text: edit.text)
    }
    let lineBreak = lineBreak(endingTheLineAt: start)
    return TextReplacement(
      range: range, text: edit.text.replacing("\n", with: lineBreak))
  }

  /// Carries out `replacement` of the file's form and returns the edit that makes the same
  /// change in the pane's form, with the text that the replacement replaced in the file.
  ///
  /// - Precondition: The replacement's range lies within the text and does not start or end
  ///   between the units of a CRLF pair.
  mutating func carryOut(_ replacement: TextReplacement) -> (edit: PaneEdit, replacedText: String) {
    precondition(
      replacement.range.lowerBound >= 0 && replacement.range.upperBound <= length,
      "The replaced range \(replacement.range) is outside the text of length \(length)")
    let utf16 = string.utf16
    let count = length
    let unit = { (offset: Int) -> UInt16? in
      offset >= 0 && offset < count ? utf16[utf16.index(utf16.startIndex, offsetBy: offset)] : nil
    }
    let replaced =
      index(
        atOffset: replacement.range.lowerBound)..<index(
        atOffset: replacement.range.upperBound)
    // Scalars, not characters: a range may end between the parts of a character.
    let replacedText = String(string.unicodeScalars[replaced])
    var lower = replacement.range.lowerBound
    var upper = replacement.range.upperBound
    var text = Array(replacement.text.utf16)
    // A carriage return and a line feed that the replacement splits apart or brings together
    // change from one line break to two or back; the edit of the pane covers the pair whole.
    let before = unit(lower - 1)
    let firstAfter = text.first ?? unit(upper)
    if before == Self.carriageReturn
      && (firstAfter == Self.lineFeed || unit(lower) == Self.lineFeed)
    {
      lower -= 1
      text.insert(Self.carriageReturn, at: 0)
    }
    let after = unit(upper)
    let lastBefore = text.last ?? unit(lower - 1)
    if after == Self.lineFeed
      && (lastBefore == Self.carriageReturn
        || upper > lower && unit(upper - 1) == Self.carriageReturn)
    {
      upper += 1
      text.append(Self.lineFeed)
    }

    let oldPaneLength = paneLength
    let oldVisibleLength = length - pairs.count
    let visibleLower = lower - pairs.partitioningIndex { $0 >= lower }
    let visibleUpper = upper - pairs.partitioningIndex { $0 >= upper }
    let visibleText = Self.visibleForm(of: text)

    string.unicodeScalars.replaceSubrange(
      index(atOffset: lower)..<index(atOffset: upper),
      with: String(decoding: text, as: UTF16.self).unicodeScalars)
    let delta = text.count - (upper - lower)
    let firstAffected = pairs.partitioningIndex { $0 >= lower }
    let firstAfterwards = pairs.partitioningIndex { $0 >= upper }
    let newPairs = text.indices.dropLast().filter {
      text[$0] == Self.carriageReturn && text[$0 + 1] == Self.lineFeed
    }.map { lower + $0 }
    pairs.replaceSubrange(
      firstAffected..<pairs.count,
      with: newPairs + pairs[firstAfterwards...].map { $0 + delta })
    length += delta

    let edit = Self.paneEdit(
      replacing: visibleLower..<visibleUpper, with: visibleText,
      oldVisibleLength: oldVisibleLength, oldPaneLength: oldPaneLength, newPaneLength: paneLength)
    return (edit, replacedText)
  }

  /// The index of the string at UTF-16 offset `offset`.
  private func index(atOffset offset: Int) -> String.Index {
    string.utf16.index(string.utf16.startIndex, offsetBy: offset)
  }

  /// The edit of the pane's text that replaces `range` of the visible text by `text`: the
  /// visible text is the file's text with a line feed for every line break, of which the pane
  /// shows all but the line break that ends the text.
  ///
  /// Only an edit that reaches the end of the visible text changes whether the text ends with a
  /// line break, and with it the end of the pane's text; it then covers that end.
  private static func paneEdit(
    replacing range: Range<Int>, with text: [UInt16], oldVisibleLength: Int, oldPaneLength: Int,
    newPaneLength: Int
  ) -> PaneEdit {
    guard range.upperBound == oldVisibleLength else {
      return PaneEdit(range: range, text: String(decoding: text, as: UTF16.self))
    }
    // The pane's text up to the start of the edit stays, unless the edit starts after the
    // line break that ended the text, or leaves a line break at the new end that the pane does
    // not show; either is the single line feed before the start.
    let lower = min(range.lowerBound, oldPaneLength, newPaneLength)
    let inserted = Array(repeating: Self.lineFeed, count: range.lowerBound - lower) + text
    return PaneEdit(
      range: lower..<oldPaneLength,
      text: String(decoding: inserted.prefix(newPaneLength - lower), as: UTF16.self))
  }

  /// The line break that ends the line in which `offset` lies, or else the one that ends the
  /// line before it, or else a line feed; a line break the pane shows as a line feed counts as
  /// one.
  private func lineBreak(endingTheLineAt offset: Int) -> String {
    let units = string.utf16
    var index = units.index(units.startIndex, offsetBy: offset)
    while index < units.endIndex {
      if Self.isLineBreak(units[index]) { return lineBreak(at: index) }
      index = units.index(after: index)
    }
    index = units.index(units.startIndex, offsetBy: offset)
    while index > units.startIndex {
      index = units.index(before: index)
      if Self.isLineBreak(units[index]) {
        // The line feed of a CRLF pair that ends the line before.
        if units[index] == Self.lineFeed, index > units.startIndex,
          units[units.index(before: index)] == Self.carriageReturn
        {
          return "\r\n"
        }
        return lineBreak(at: index)
      }
    }
    return "\n"
  }

  /// The line break that starts at `index`: CRLF, CR, or a line feed for any other.
  private func lineBreak(at index: String.UTF16View.Index) -> String {
    let units = string.utf16
    guard units[index] == Self.carriageReturn else { return "\n" }
    let next = units.index(after: index)
    return next < units.endIndex && units[next] == Self.lineFeed ? "\r\n" : "\r"
  }

  /// `text` with a line feed for every line break.
  static func visibleForm(of text: String) -> String {
    String(decoding: visibleForm(of: Array(text.utf16)), as: UTF16.self)
  }

  /// `units` with a line feed for every line break.
  private static func visibleForm(of units: [UInt16]) -> [UInt16] {
    var result: [UInt16] = []
    result.reserveCapacity(units.count)
    for (index, unit) in units.enumerated() {
      if unit == lineFeed && index > 0 && units[index - 1] == carriageReturn { continue }
      result.append(isLineBreak(unit) ? lineFeed : unit)
    }
    return result
  }

  /// Whether a UTF-16 code unit breaks a line in the text system.
  private static func isLineBreak(_ unit: UInt16) -> Bool {
    unit == lineFeed || unit == carriageReturn || unit == 0x85 || unit == 0x2028 || unit == 0x2029
  }

  private static let lineFeed = UInt16(UInt8(ascii: "\n"))
  private static let carriageReturn = UInt16(UInt8(ascii: "\r"))
}
