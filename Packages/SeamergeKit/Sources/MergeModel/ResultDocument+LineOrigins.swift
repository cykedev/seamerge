/// Where a line of the result comes from: the inputs whose text holds it, or nobody for a line
/// typed by hand.
public struct LineOrigin: Sendable, Hashable {
  /// The line, its line break included, as a UTF-16 range of the result text.
  public let range: Range<Int>

  /// The inputs whose text holds the line, as their toggle has them, in the order base, A, B;
  /// empty for a line typed by hand.
  public let roles: [Role]
}

extension ResultDocument {
  /// Where each line of `text`, the result text, comes from, for the segments whose lines come
  /// from more than one place: segments edited by hand, and segments that take the texts of
  /// several toggles, such as A then B.
  ///
  /// A line comes from the toggle whose text has it where it stands, compared line by line with
  /// the texts of the segment's toggles in their order; a line that they do not have was typed
  /// by hand. The origins follow from the text alone, so a line typed back word for word as its
  /// source has it comes from the source again. An edited conflict without sources is compared
  /// with A's lines then B's, where resolving it by hand starts; any other segment with the texts
  /// of its sources, which have no lines if it takes nothing.
  ///
  /// - Parameter text: The result text, as long as the segments together.
  /// - Returns: The origins in the order of the lines; segments with lines from a single place
  ///   have none.
  public func lineOrigins(of text: String) -> [LineOrigin] {
    var origins: [LineOrigin] = []
    var start = 0
    for (index, segmentText) in split(text).enumerated() {
      defer { start += segments[index].length }
      let toggles = sourceToggles(ofSegment: index)
      guard segments[index].state == .edited || toggles.count > 1 else { continue }
      let reference = toggles.flatMap { toggle in
        Self.lines(of: toggle.text[...]).map { (text: $0.text, roles: toggle.roles) }
      }
      for (line, roles) in Self.origins(of: Self.lines(of: segmentText), in: reference) {
        origins.append(
          LineOrigin(
            range: start + line.range.lowerBound..<start + line.range.upperBound, roles: roles))
      }
    }
    return origins
  }

  /// The toggles whose texts the segment at `index` takes or started from, in order: those its
  /// sources switch on, or, for an edited conflict without sources, A's and B's.
  private func sourceToggles(ofSegment index: Int) -> [Toggle] {
    let block = session.blocks[index]
    let toggles = texts.toggles(in: block)
    let segment = segments[index]
    if segment.sources.isEmpty && segment.state == .edited && block.kind == .conflict {
      return [Role.a, .b].map { SegmentTexts.toggle(for: $0, among: toggles) }
    }
    return SegmentTexts.toggles(switchedOnBy: segment.sources, among: toggles)
  }

  /// A line of a text: its characters without the line break, and its UTF-16 range within the
  /// text with the break.
  private struct Line {
    let text: Substring
    let range: Range<Int>
  }

  /// The lines of `text`, split where the text system breaks lines: at CR, LF, CRLF, NEL,
  /// U+2028 and U+2029; a text that ends with a break has no line after it.
  private static func lines(of text: Substring) -> [Line] {
    var lines: [Line] = []
    var lineStart = text.startIndex
    var offset = 0
    var lineOffset = 0
    var index = text.startIndex
    while index < text.endIndex {
      let character = text[index]
      let next = text.index(after: index)
      offset += character.utf16.count
      // CRLF is a single character in Swift, as it is a single break.
      if Self.lineBreaks.contains(character) {
        lines.append(Line(text: text[lineStart..<index], range: lineOffset..<offset))
        lineStart = next
        lineOffset = offset
      }
      index = next
    }
    if lineStart < text.endIndex {
      lines.append(Line(text: text[lineStart...], range: lineOffset..<offset))
    }
    return lines
  }

  /// The characters that break lines in the text system; unlike `Character.isNewline`, form
  /// feed and vertical tab do not.
  private static let lineBreaks: Set<Character> = [
    "\n", "\r", "\r\n", "\u{85}", "\u{2028}", "\u{2029}",
  ]

  /// Each of `lines` with the roles of the line of `reference` that the longest common
  /// subsequence of both pairs it with, or no roles if it pairs it with none.
  ///
  /// Lines at the start and the end that both have in common are paired first, so that a small
  /// edit in a long segment costs little.
  private static func origins(
    of lines: [Line], in reference: [(text: Substring, roles: [Role])]
  ) -> [(Line, [Role])] {
    var prefix = 0
    while prefix < lines.count && prefix < reference.count
      && lines[prefix].text == reference[prefix].text
    {
      prefix += 1
    }
    var suffix = 0
    while suffix < lines.count - prefix && suffix < reference.count - prefix
      && lines[lines.count - 1 - suffix].text == reference[reference.count - 1 - suffix].text
    {
      suffix += 1
    }
    let middle = lines[prefix..<lines.count - suffix]
    let referenceMiddle = reference[prefix..<reference.count - suffix]
    let difference = middle.map(\.text).difference(from: referenceMiddle.map(\.text))
    var inserted = Set<Int>()
    var removed = Set<Int>()
    for change in difference {
      switch change {
      case .insert(let offset, _, _): inserted.insert(offset)
      case .remove(let offset, _, _): removed.insert(offset)
      }
    }
    // The lines that stay pair up in order with the reference lines that stay.
    var kept = referenceMiddle.indices.filter { !removed.contains($0 - prefix) }.makeIterator()
    var origins = zip(lines[..<prefix], reference[..<prefix]).map { ($0, $1.roles) }
    for (offset, line) in middle.enumerated() {
      if inserted.contains(offset) {
        origins.append((line, []))
      } else if let index = kept.next() {
        origins.append((line, reference[index].roles))
      }
    }
    origins += zip(lines[(lines.count - suffix)...], reference[(reference.count - suffix)...]).map {
      ($0, $1.roles)
    }
    return origins
  }
}
