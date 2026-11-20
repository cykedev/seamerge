import Foundation

/// The texts that the segments of a result take from the inputs, and how they are joined.
///
/// The texts keep the bytes of the files: a file whose lines all end in CR is compared as if they
/// ended in LF, but its lines keep CR here, because the result is written as text of the same
/// files. Texts are joined the way the engine joins them, so that a result without hand edits has
/// the same bytes as the engine's.
struct SegmentTexts: Sendable {
  /// The files of the session.
  private let files: Session.Inputs<ComparedFile>

  /// The inputs that take part, in the order base, A, B.
  private let roles: [Role]

  /// The line ending that ends a text which would otherwise run into the text after it, and that
  /// ends every conflict marker.
  ///
  /// As in the engine, it is the first line ending found in B, A or the base, in that order, or
  /// LF if none of them has one.
  let lineEnding: String

  /// The blocks whose text in some input may end without a line ending, because they hold the
  /// last line of a file that does not end with one; in ascending order.
  let blocksEndingWithoutLineEnding: [Int]

  /// The line that the preview of a conflict shows in place of the lines of a side that removed
  /// them, by side.
  let removalNotes: [Role: String]

  /// Prepares the texts of `blocks` from `files`, with `removalNotes` for the previews of
  /// conflicts in which a side removed the lines of the base.
  init(files: Session.Inputs<ComparedFile>, blocks: [Block], removalNotes: [Role: String]) {
    self.files = files
    self.removalNotes = removalNotes
    roles = files.roles
    lineEnding =
      [Role.b, .a, .base].lazy.compactMap { files[$0]?.file.utf8 }.compactMap(Self.lineEnding(in:))
      .first ?? "\n"
    var endingBlocks: Set<Int> = []
    for (role, file) in files {
      guard let bytes = file.file.utf8, let last = bytes.last,
        last != UInt8(ascii: "\n"), last != UInt8(ascii: "\r"),
        let block = blocks.last(where: { !$0.lines(in: role).isEmpty })
      else { continue }
      endingBlocks.insert(block.id)
    }
    blocksEndingWithoutLineEnding = endingBlocks.sorted()
  }

  /// The text of `role` in `block`, including the line ending of its last line; empty if the
  /// input does not take part.
  func text(of role: Role, in block: Block) -> String {
    files[role]?.originalText(ofLines: block.lines(in: role)) ?? ""
  }

  /// The toggles of `block`, one for each different text, ordered by their first input.
  func toggles(in block: Block) -> [Toggle] {
    var versions: [(roles: [Role], text: String)] = []
    for role in roles {
      let text = text(of: role, in: block)
      if let index = versions.firstIndex(where: { $0.text.utf8.elementsEqual(text.utf8) }) {
        versions[index].roles.append(role)
      } else {
        versions.append(([role], text))
      }
    }
    // The base shares a toggle only with inputs of the same text, so an empty version beside a
    // base with lines never includes the base.
    let baseHasLines = !text(of: .base, in: block).isEmpty
    return versions.map { version in
      Toggle(
        roles: version.roles, kind: version.text.isEmpty && baseHasLines ? .deletion : .version,
        text: version.text)
    }
  }

  /// The segment of `block` after loading, without its length.
  ///
  /// A conflict is open. Every other block takes the source the engine takes: the side that
  /// changed it, or B where B's text counts as equal to another side's.
  func initialSegment(for block: Block) -> Segment {
    let toggles = toggles(in: block)
    switch block.kind {
    case .conflict:
      return Segment(state: .open)
    case .unchanged:
      return Segment(state: .untouched, sources: Self.toggle(for: .b, among: toggles).roles)
    case .changedInA:
      return Segment(state: .auto, sources: Self.toggle(for: .a, among: toggles).roles)
    case .changedInB, .changedInBoth:
      return Segment(state: .auto, sources: Self.toggle(for: .b, among: toggles).roles)
    case .changed:
      preconditionFailure("A comparison of two files has no result")
    }
  }

  /// The preview of a conflict: A's lines, then B's lines, each ending with a line ending; a side
  /// that removed the lines of the base shows its removal note in their place, if it has one.
  ///
  /// The preview is never written, so it always ends with a line ending, regardless of what
  /// follows it.
  func previewText(for block: Block) -> String {
    joined([Role.a, .b].map { previewPart(of: $0, in: block) }, followedByText: true)
  }

  /// The texts of a conflict as a preview shows them, A's lines then B's, without removal
  /// notes: what resolving the conflict by hand starts from.
  func sideTexts(of block: Block) -> String {
    joined([text(of: .a, in: block), text(of: .b, in: block)], followedByText: true)
  }

  /// What the preview of a conflict shows for `role`: its lines, or its removal note if it
  /// removed the lines of the base and has a note.
  func previewPart(of role: Role, in block: Block) -> String {
    let text = text(of: role, in: block)
    guard text.isEmpty, !self.text(of: .base, in: block).isEmpty, let note = removalNotes[role]
    else { return text }
    return note
  }

  /// The text of a segment that is not edited.
  ///
  /// - Parameter followedByText: Whether a later segment has text, so that a text ending without
  ///   a line ending gets one.
  func text(of segment: Segment, in block: Block, followedByText: Bool) -> String {
    switch segment.state {
    case .open:
      return previewText(for: block)
    case .edited:
      preconditionFailure("Only the result holds the text of an edited segment")
    case .untouched, .auto, .chosen:
      let toggles = Self.toggles(switchedOnBy: segment.sources, among: toggles(in: block))
      return joined(toggles.map(\.text), followedByText: followedByText)
    }
  }

  /// The text of each of `segments`, which belong to `blocks`.
  ///
  /// - Parameter editedTexts: The text of each edited segment, by index.
  func texts(of segments: [Segment], in blocks: [Block], editedTexts: [Int: String]) -> [String] {
    var texts = [String](repeating: "", count: segments.count)
    var followedByText = false
    for index in segments.indices.reversed() {
      if segments[index].state == .edited {
        guard let text = editedTexts[index] else {
          preconditionFailure("Edited segment \(index) has no text")
        }
        texts[index] = text
      } else {
        texts[index] = text(
          of: segments[index], in: blocks[index], followedByText: followedByText)
      }
      followedByText = followedByText || !texts[index].isEmpty
    }
    return texts
  }

  /// Joins `parts` the way the engine joins texts: a part that ends without a line ending gets
  /// one if text follows, within `parts` or, when `followedByText` is set, after them.
  func joined(_ parts: [String], followedByText: Bool) -> String {
    let lastText = parts.lastIndex { !$0.isEmpty }
    var result = ""
    for (index, part) in parts.enumerated() {
      result += part
      guard let lastText, index < lastText || followedByText && index == lastText else {
        continue
      }
      if !part.isEmpty && !Self.endsWithLineEnding(part) {
        result += lineEnding
      }
    }
    return result
  }

  /// Whether `text` ends with LF or CR, the line endings the engine splits lines at.
  static func endsWithLineEnding(_ text: String) -> Bool {
    text.utf8.last == UInt8(ascii: "\n") || text.utf8.last == UInt8(ascii: "\r")
  }

  /// The toggle of `role`.
  ///
  /// - Precondition: `role` takes part in the session.
  static func toggle(for role: Role, among toggles: [Toggle]) -> Toggle {
    guard let toggle = toggles.first(where: { $0.roles.contains(role) }) else {
      preconditionFailure("The input \(role) does not take part")
    }
    return toggle
  }

  /// The toggles that `sources` switch on, in the order they were switched on.
  static func toggles(switchedOnBy sources: [Role], among toggles: [Toggle]) -> [Toggle] {
    var switchedOn: [Toggle] = []
    for role in sources {
      let toggle = toggle(for: role, among: toggles)
      if !switchedOn.contains(toggle) {
        switchedOn.append(toggle)
      }
    }
    return switchedOn
  }

  /// The first line ending in `bytes`: CRLF or LF at the first LF, otherwise CR if there is one.
  private static func lineEnding(in bytes: Data) -> String? {
    if let index = bytes.firstIndex(of: UInt8(ascii: "\n")) {
      return index > bytes.startIndex && bytes[index - 1] == UInt8(ascii: "\r") ? "\r\n" : "\n"
    }
    return bytes.contains(UInt8(ascii: "\r")) ? "\r" : nil
  }
}
