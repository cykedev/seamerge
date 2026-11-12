/// The lexer for markup: comments, tags and attribute values in HTML and XML; headings, fenced
/// code and code spans in Markdown.
///
/// Like the lexer for code, each step moves past at least one byte or into a construct that
/// will, and looks at most a bounded number of bytes ahead.
struct MarkupLexer: Sendable {
  private struct Tags {
    let characterData: (open: [UInt8], close: [UInt8])?
    let rawTextElements: [[UInt8]]
  }

  private struct Lightweight {
    let headingMarker: UInt8
    let codeFenceMarkers: ByteSet
    let codeSpanMarker: UInt8
  }

  /// The fewest markers that make a code fence.
  private static let minimumFenceLength = 3

  /// The most heading markers that start a heading.
  private static let maximumHeadingLevel = 6

  private static let nameCharacters = ByteSet.asciiWordCharacters.union(.nonASCII)
    .union(ByteSet([":", ".", "-"]))

  private let commentOpen: [UInt8]
  private let commentClose: [UInt8]
  private let tags: Tags?
  private let lightweight: Lightweight?

  init(_ syntax: MarkupSyntax) {
    commentOpen = Array(syntax.comment.open.utf8)
    commentClose = Array(syntax.comment.close.utf8)
    precondition(!commentOpen.isEmpty && !commentClose.isEmpty, "Comment delimiters are empty")
    tags = syntax.tags.map { tags in
      Tags(
        characterData: tags.characterData.map { (Array($0.open.utf8), Array($0.close.utf8)) },
        rawTextElements: tags.rawTextElements.map { Array($0.lowercased().utf8) })
    }
    lightweight = syntax.lightweight.map { lightweight in
      Lightweight(
        headingMarker: Self.asciiByte(lightweight.headingMarker),
        codeFenceMarkers: ByteSet(lightweight.codeFenceMarkers),
        codeSpanMarker: Self.asciiByte(lightweight.codeSpanMarker))
    }
  }

  private static func asciiByte(_ character: Character) -> UInt8 {
    guard let byte = character.asciiValue else {
      preconditionFailure("Markup markers must be ASCII characters")
    }
    return byte
  }

  /// Lexes one line, starting with the constructs open at the end of the line before.
  func lex(_ line: LineBytes, contexts: inout [LexerContext], tokens: inout TokenList) {
    if let lightweight, lexBlock(line, lightweight, contexts: &contexts, tokens: &tokens) {
      return
    }
    var codeSpans = lightweight.map { CodeSpanRuns(marker: $0.codeSpanMarker, in: line) }
    var position = 0
    while position < line.count {
      switch contexts.last {
      case .markupComment:
        position = continueDelimited(
          until: commentClose, as: .comment, in: line, from: position, contexts: &contexts,
          tokens: &tokens)
      case .characterData:
        position = continueDelimited(
          until: tags?.characterData?.close ?? [], as: .string, in: line, from: position,
          contexts: &contexts, tokens: &tokens)
      case .rawText(let element):
        position = continueRawText(element, in: line, from: position, contexts: &contexts)
      case .tag(let rawTextElement):
        position = lexInsideTag(
          rawTextElement, at: position, in: line, contexts: &contexts, tokens: &tokens)
      case .attributeValue(let quote):
        position = continueQuoted(
          quote, in: line, from: position, contexts: &contexts, tokens: &tokens)
      default:
        position = lexText(
          at: position, in: line, codeSpans: &codeSpans, contexts: &contexts, tokens: &tokens)
      }
    }
  }

  /// Lexes a line that is a heading, a code fence or inside fenced code, as a whole.
  ///
  /// - Returns: Whether the line was such a line.
  private func lexBlock(
    _ line: LineBytes, _ lightweight: Lightweight, contexts: inout [LexerContext],
    tokens: inout TokenList
  ) -> Bool {
    let start = line.skippingSpaces(from: 0)
    if case .fencedCode(let marker, let length) = contexts.last {
      tokens.add(start..<line.count, .string)
      let fence = runLength(of: marker, in: line, at: start)
      if fence >= length, line.skippingSpaces(from: start + fence) == line.count {
        contexts.removeLast()
      }
      return true
    }
    guard contexts.isEmpty, let first = line.byte(at: start) else { return false }
    if lightweight.codeFenceMarkers.contains(first) {
      let fence = runLength(of: first, in: line, at: start)
      // An info string after a fence of the code span marker must not contain that marker.
      let isFence =
        fence >= Self.minimumFenceLength
        && (first != lightweight.codeSpanMarker
          || line.firstPosition(of: first, from: start + fence) == nil)
      if isFence {
        contexts.append(.fencedCode(marker: first, length: fence))
        tokens.add(start..<line.count, .string)
        return true
      }
    }
    if first == lightweight.headingMarker {
      let level = runLength(of: first, in: line, at: start)
      let next = line.byte(at: start + level)
      if level <= Self.maximumHeadingLevel, next == nil || next?.isSpaceOrTab == true {
        tokens.add(start..<line.count, .keyword)
        return true
      }
    }
    return false
  }

  private func runLength(of marker: UInt8, in line: LineBytes, at start: Int) -> Int {
    var end = start
    while line.byte(at: end) == marker { end += 1 }
    return end - start
  }

  /// One step in text: opens a comment, character data, a tag or a code span, or moves on.
  private func lexText(
    at position: Int, in line: LineBytes, codeSpans: inout CodeSpanRuns?,
    contexts: inout [LexerContext], tokens: inout TokenList
  ) -> Int {
    let byte = line[position]
    if byte == commentOpen[0], line.hasPrefix(commentOpen, at: position) {
      contexts.append(.markupComment)
      tokens.add(position..<position + commentOpen.count, .comment)
      return position + commentOpen.count
    }
    if let tags, byte == UInt8(ascii: "<") {
      if let characterData = tags.characterData,
        line.hasPrefix(characterData.open, at: position)
      {
        contexts.append(.characterData)
        tokens.add(position..<position + characterData.open.count, .string)
        return position + characterData.open.count
      }
      if let end = openTag(tags, at: position, in: line, contexts: &contexts, tokens: &tokens) {
        return end
      }
    }
    if let lightweight, byte == lightweight.codeSpanMarker, var runs = codeSpans {
      let span = runs.end(ofSpanStartingAt: position)
      codeSpans = runs
      if span.isCodeSpan { tokens.add(position..<span.end, .string) }
      return span.end
    }
    return position + 1
  }

  /// Opens a tag at a `<`, coloring its name, if a name follows.
  private func openTag(
    _ tags: Tags, at position: Int, in line: LineBytes, contexts: inout [LexerContext],
    tokens: inout TokenList
  ) -> Int? {
    var nameStart = position + 1
    let marker = line.byte(at: nameStart)
    let isOpeningTag = marker.map { Self.nameCharacters.contains($0) } ?? false
    if marker == UInt8(ascii: "/") || marker == UInt8(ascii: "!") || marker == UInt8(ascii: "?") {
      nameStart += 1
    }
    guard let first = line.byte(at: nameStart), first.isASCIILetter else { return nil }
    var nameEnd = nameStart + 1
    while let byte = line.byte(at: nameEnd), Self.nameCharacters.contains(byte) { nameEnd += 1 }
    let rawTextElement =
      isOpeningTag
      ? tags.rawTextElements.firstIndex {
        $0.count == nameEnd - nameStart && line.hasPrefix(lowercased: $0, at: nameStart)
      } : nil
    contexts.append(.tag(rawTextElement: rawTextElement))
    tokens.add(nameStart..<nameEnd, .keyword)
    return nameEnd
  }

  /// One step inside a tag: an attribute value, the end of the tag, or a word.
  private func lexInsideTag(
    _ rawTextElement: Int?, at position: Int, in line: LineBytes,
    contexts: inout [LexerContext], tokens: inout TokenList
  ) -> Int {
    let byte = line[position]
    let next = line.byte(at: position + 1)
    switch byte {
    case UInt8(ascii: ">"):
      contexts.removeLast()
      if let rawTextElement { contexts.append(.rawText(element: rawTextElement)) }
      return position + 1
    case UInt8(ascii: "/") where next == UInt8(ascii: ">"),
      UInt8(ascii: "?") where next == UInt8(ascii: ">"):
      contexts.removeLast()
      return position + 2
    case UInt8(ascii: "\""), UInt8(ascii: "'"):
      contexts.append(.attributeValue(quote: byte))
      tokens.add(position..<position + 1, .string)
      return position + 1
    default:
      return position + 1
    }
  }

  private func continueQuoted(
    _ quote: UInt8, in line: LineBytes, from start: Int, contexts: inout [LexerContext],
    tokens: inout TokenList
  ) -> Int {
    guard let close = line.firstPosition(of: quote, from: start) else {
      tokens.add(start..<line.count, .string)
      return line.count
    }
    contexts.removeLast()
    tokens.add(start..<close + 1, .string)
    return close + 1
  }

  private func continueDelimited(
    until close: [UInt8], as kind: TokenKind, in line: LineBytes, from start: Int,
    contexts: inout [LexerContext], tokens: inout TokenList
  ) -> Int {
    var position = start
    while position < line.count {
      if line.hasPrefix(close, at: position) {
        contexts.removeLast()
        tokens.add(start..<position + close.count, kind)
        return position + close.count
      }
      position += 1
    }
    tokens.add(start..<line.count, kind)
    return line.count
  }

  /// Skips the content of an element such as `script` up to its closing tag, which is then
  /// lexed as a tag.
  private func continueRawText(
    _ element: Int, in line: LineBytes, from start: Int, contexts: inout [LexerContext]
  ) -> Int {
    let name = tags?.rawTextElements[element] ?? []
    var position = start
    while let open = line.firstPosition(of: UInt8(ascii: "<"), from: position) {
      let nameEnd = open + 2 + name.count
      if line.byte(at: open + 1) == UInt8(ascii: "/"),
        line.hasPrefix(lowercased: name, at: open + 2),
        line.byte(at: nameEnd).map({ !Self.nameCharacters.contains($0) }) ?? true
      {
        contexts.removeLast()
        return open
      }
      position = open + 1
    }
    return line.count
  }
}
