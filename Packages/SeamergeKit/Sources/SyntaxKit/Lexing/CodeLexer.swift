/// The lexer for programming languages: comments, strings with their interpolations, here
/// documents, numbers and keywords.
///
/// Each step of the automaton starts at a position, looks at the innermost open construct and
/// moves past at least one byte or into a construct that will. A step looks at most a bounded
/// number of bytes ahead, so a line takes time in proportion to its length.
struct CodeLexer: Sendable {
  /// The deepest nesting of interpolations taken as such; deeper ones are plain string
  /// content, which bounds the size of the lexer state.
  private static let maximumNesting = 16

  private let keywords: KeywordTable
  private let lineComments: [[UInt8]]
  private let lineCommentsStartWords: Bool
  private let blockComments: [(open: [UInt8], close: [UInt8], syntax: BlockCommentSyntax)]
  private let strings: [StringRule]
  private let hereDocuments: HereDocumentRule?
  private let keywordPrefixes: ByteSet
  private let wordStarts: ByteSet
  private let wordCharacters: ByteSet
  private let digitSeparators: ByteSet
  /// The bytes that may start a comment, a string or a here document.
  private let constructStarts: ByteSet

  init(_ syntax: CodeSyntax) {
    keywords = KeywordTable(syntax.keywords, ignoresCase: syntax.keywordsIgnoreCase)
    lineComments = syntax.lineComments.map { Array($0.utf8) }
    lineCommentsStartWords = syntax.lineCommentsStartWords
    blockComments = syntax.blockComments.map { (Array($0.open.utf8), Array($0.close.utf8), $0) }
    strings = syntax.strings.map(StringRule.init)
    hereDocuments = syntax.hereDocuments.map(HereDocumentRule.init)
    keywordPrefixes = ByteSet(syntax.keywordPrefixes)
    wordCharacters = ByteSet.asciiWordCharacters.union(.nonASCII)
      .union(ByteSet(syntax.wordCharacters))
    wordStarts = wordCharacters.subtracting(ByteSet(UInt8(ascii: "0")...UInt8(ascii: "9")))
      .subtracting(ByteSet(syntax.wordCharacters))
      .union(keywordPrefixes).union(ByteSet(syntax.variablePrefixes))
    digitSeparators = ByteSet(syntax.digitSeparators)
    precondition(
      !lineComments.contains(where: \.isEmpty)
        && !blockComments.contains(where: { $0.open.isEmpty || $0.close.isEmpty }),
      "Comment delimiters must not be empty")
    var constructStarts = ByteSet(syntax.lineComments.compactMap(\.first))
      .union(ByteSet(syntax.blockComments.compactMap(\.open.first)))
    for rule in strings { constructStarts = constructStarts.union(rule.firstBytes) }
    if let hereDocuments { constructStarts = constructStarts.union(hereDocuments.firstBytes) }
    self.constructStarts = constructStarts
  }

  /// Lexes one line, starting with the constructs open at the end of the line before.
  func lex(_ line: LineBytes, contexts: inout [LexerContext], tokens: inout TokenList) {
    if case .hereDocument(let terminator) = contexts.last {
      tokens.add(0..<line.count, .string)
      if hereDocuments?.isTerminator(terminator, line) == true { contexts.removeLast() }
      return
    }
    var pendingHereDocument: [UInt8]?
    var position = 0
    while position < line.count {
      switch contexts.last {
      case .blockComment(let rule, let depth):
        position = continueBlockComment(
          rule, depth: depth, in: line, from: position, contexts: &contexts, tokens: &tokens)
      case .string(let rule, let delimiter):
        position = continueString(
          rule, delimiter: delimiter, in: line, from: position, contexts: &contexts,
          tokens: &tokens)
      default:
        position = lexCode(
          at: position, in: line, contexts: &contexts, tokens: &tokens,
          pendingHereDocument: &pendingHereDocument)
      }
    }
    // A string that cannot span lines ends with its line, and with it what is open inside.
    if let firstSingleLine = contexts.firstIndex(where: isSingleLineString) {
      contexts.removeSubrange(firstSingleLine...)
    }
    if let pendingHereDocument { contexts.append(.hereDocument(terminator: pendingHereDocument)) }
  }

  private func isSingleLineString(_ context: LexerContext) -> Bool {
    if case .string(let rule, _) = context { !strings[rule].spansLines } else { false }
  }

  /// One step outside comments and strings, at the top level or inside an interpolation.
  private func lexCode(
    at position: Int, in line: LineBytes, contexts: inout [LexerContext],
    tokens: inout TokenList, pendingHereDocument: inout [UInt8]?
  ) -> Int {
    let byte = line[position]
    if case .interpolation(let close, let depth) = contexts.last {
      if byte == close {
        // The string resumes with the closing bracket, which belongs to it.
        guard depth == 0 else {
          contexts[contexts.count - 1] = .interpolation(close: close, depth: depth - 1)
          return position + 1
        }
        contexts.removeLast()
        return position
      }
      if byte == Self.openingBracket(for: close) {
        contexts[contexts.count - 1] = .interpolation(close: close, depth: depth + 1)
        return position + 1
      }
    }
    if constructStarts.contains(byte),
      let end = lexConstruct(
        at: position, in: line, contexts: &contexts, tokens: &tokens,
        pendingHereDocument: &pendingHereDocument)
    {
      return end
    }
    if byte.isASCIIDigit || (byte == UInt8(ascii: ".") && startsFraction(line, at: position)) {
      let end = numberEnd(in: line, from: position)
      tokens.add(position..<end, .number)
      return end
    }
    if wordStarts.contains(byte) {
      var end = position + 1
      while let next = line.byte(at: end), wordCharacters.contains(next) { end += 1 }
      let isPrefixedKeyword = keywordPrefixes.contains(byte) && end - position > 1
      if isPrefixedKeyword || keywords.contains(position..<end, in: line) {
        tokens.add(position..<end, .keyword)
      }
      return end
    }
    return position + 1
  }

  /// Opens a comment, string or here document at a position, if one starts there, and returns
  /// the position after its opening.
  private func lexConstruct(
    at position: Int, in line: LineBytes, contexts: inout [LexerContext],
    tokens: inout TokenList, pendingHereDocument: inout [UInt8]?
  ) -> Int? {
    if startsLineComment(line, at: position) {
      tokens.add(position..<line.count, .comment)
      return line.count
    }
    for (rule, comment) in blockComments.enumerated()
    where line.hasPrefix(comment.open, at: position)
      && (!comment.syntax.standsOnOwnLines || position == 0)
    {
      contexts.append(.blockComment(rule: rule, depth: 0))
      tokens.add(position..<position + comment.open.count, .comment)
      return position + comment.open.count
    }
    if let hereDocuments, let introduction = hereDocuments.introduction(in: line, at: position) {
      tokens.add(position..<introduction.end, .string)
      // Only the first here document of a line is read; a second one is rare.
      if pendingHereDocument == nil { pendingHereDocument = introduction.terminator }
      return introduction.end
    }
    for (rule, string) in strings.enumerated() {
      guard let opening = string.opening(in: line, at: position) else { continue }
      contexts.append(.string(rule: rule, delimiter: opening.delimiter))
      tokens.add(position..<opening.contentStart, .string)
      return opening.contentStart
    }
    return nil
  }

  private func startsLineComment(_ line: LineBytes, at position: Int) -> Bool {
    guard lineComments.contains(where: { line.hasPrefix($0, at: position) }) else {
      return false
    }
    guard lineCommentsStartWords, position > 0 else { return true }
    return Self.wordBoundaries.contains(line[position - 1])
  }

  /// The bytes after which a shell word begins.
  private static let wordBoundaries = ByteSet([" ", "\t", ";", "&", "|", "(", ")"])

  private func continueBlockComment(
    _ rule: Int, depth: Int, in line: LineBytes, from start: Int,
    contexts: inout [LexerContext], tokens: inout TokenList
  ) -> Int {
    let comment = blockComments[rule]
    if comment.syntax.standsOnOwnLines {
      if start == 0, line.hasPrefix(comment.close, at: 0) { contexts.removeLast() }
      tokens.add(start..<line.count, .comment)
      return line.count
    }
    var depth = depth
    var position = start
    while position < line.count {
      if line.hasPrefix(comment.close, at: position) {
        position += comment.close.count
        if depth == 0 {
          contexts.removeLast()
          tokens.add(start..<position, .comment)
          return position
        }
        depth -= 1
      } else if comment.syntax.nests, line.hasPrefix(comment.open, at: position) {
        position += comment.open.count
        depth += 1
      } else {
        position += 1
      }
    }
    contexts[contexts.count - 1] = .blockComment(rule: rule, depth: depth)
    tokens.add(start..<line.count, .comment)
    return line.count
  }

  private func continueString(
    _ rule: Int, delimiter: [UInt8], in line: LineBytes, from start: Int,
    contexts: inout [LexerContext], tokens: inout TokenList
  ) -> Int {
    var position = start
    while true {
      switch strings[rule].scanContent(in: line, from: position, delimiter: delimiter) {
      case .closed(let end):
        contexts.removeLast()
        tokens.add(start..<end, .string)
        return end
      case .interpolation(let end, let close):
        // Too deep an interpolation stays part of the string.
        guard contexts.count < Self.maximumNesting else {
          position = end
          continue
        }
        contexts.append(.interpolation(close: close, depth: 0))
        tokens.add(start..<end, .string)
        return end
      case .lineEnd:
        tokens.add(start..<line.count, .string)
        return line.count
      }
    }
  }

  /// Whether a period at a position starts a number such as `.5`, rather than following a
  /// word, a number or another period.
  private func startsFraction(_ line: LineBytes, at position: Int) -> Bool {
    guard line.byte(at: position + 1)?.isASCIIDigit == true else { return false }
    guard position > 0 else { return true }
    let previous = line[position - 1]
    return !wordCharacters.contains(previous) && previous != UInt8(ascii: ".")
      && previous != UInt8(ascii: ")") && previous != UInt8(ascii: "]")
  }

  /// The end of a number: digits, letters for its base, exponent and suffix, a fraction, and
  /// digit separators between digits.
  private func numberEnd(in line: LineBytes, from start: Int) -> Int {
    let isHexadecimal =
      line[start] == UInt8(ascii: "0")
      && line.byte(at: start + 1)?.lowercasedASCII == UInt8(ascii: "x")
    let exponentMarker = isHexadecimal ? UInt8(ascii: "p") : UInt8(ascii: "e")
    var position = start
    while let byte = line.byte(at: position) {
      let next = line.byte(at: position + 1)
      if ByteSet.asciiWordCharacters.contains(byte) {
        position += 1
        if byte.lowercasedASCII == exponentMarker,
          next == UInt8(ascii: "+") || next == UInt8(ascii: "-"),
          line.byte(at: position + 1)?.isASCIIDigit == true
        {
          position += 1
        }
      } else if byte == UInt8(ascii: "."), next?.isASCIIDigit == true {
        position += 1
      } else if digitSeparators.contains(byte), let next,
        ByteSet.asciiWordCharacters.contains(next)
      {
        position += 1
      } else {
        break
      }
    }
    return position
  }

  private static func openingBracket(for close: UInt8) -> UInt8? {
    switch close {
    case UInt8(ascii: ")"): UInt8(ascii: "(")
    case UInt8(ascii: "}"): UInt8(ascii: "{")
    case UInt8(ascii: "]"): UInt8(ascii: "[")
    default: nil
    }
  }
}
