/// The lexer for data formats: comments, quoted strings, block scalars, and plain scalars that
/// are numbers or keywords as a whole.
///
/// Each step moves past at least one byte, and looks at most a bounded number of bytes ahead,
/// apart from the look past the spaces after a word.
struct DataLexer: Sendable {
  /// Where a line stands in its structure, for finding the parent of a block scalar.
  private struct LineStructure {
    /// The column of the last sequence indicator before the first item of the line.
    var lastIndicatorColumn: Int?
    /// The column of the first item of the line that is not a sequence indicator.
    var firstItemColumn: Int?
  }

  /// The punctuation of flow collections, which ends a plain word.
  private static let flowDelimiters = ByteSet([",", "[", "]", "{", "}"])

  /// The bytes after which a scalar starts.
  private static let scalarStarts = ByteSet([",", "[", "{"])

  /// The bytes before which a scalar ends.
  private static let scalarEnds = ByteSet([",", "]", "}"])

  /// The characters that may follow a block scalar indicator: indentation and chomping.
  private static let blockScalarModifiers = ByteSet(UInt8(ascii: "0")...UInt8(ascii: "9"))
    .union(ByteSet(["+", "-"]))

  private let keywords: KeywordTable
  private let lineComments: [[UInt8]]
  private let commentsNeedPrecedingSpace: Bool
  private let strings: [StringRule]
  private let separator: UInt8
  private let separatorNeedsSpace: Bool
  private let sequenceIndicator: UInt8?
  private let blockScalarIndicators: ByteSet

  init(_ syntax: DataSyntax) {
    precondition(
      syntax.strings.allSatisfy { $0.interpolations.isEmpty },
      "Strings in data have no interpolations")
    keywords = KeywordTable(syntax.keywords, ignoresCase: false)
    lineComments = syntax.lineComments.map { Array($0.utf8) }
    precondition(!lineComments.contains(where: \.isEmpty), "Comment delimiters must not be empty")
    commentsNeedPrecedingSpace = syntax.commentsNeedPrecedingSpace
    strings = syntax.strings.map(StringRule.init)
    guard let separator = syntax.keyValueSeparator.asciiValue,
      syntax.sequenceIndicator.map({ $0.isASCII }) ?? true
    else { preconditionFailure("Data separators must be ASCII characters") }
    self.separator = separator
    separatorNeedsSpace = syntax.separatorNeedsSpace
    sequenceIndicator = syntax.sequenceIndicator?.asciiValue
    blockScalarIndicators = ByteSet(syntax.blockScalarIndicators)
  }

  /// Lexes one line, starting with the constructs open at the end of the line before.
  func lex(_ line: LineBytes, contexts: inout [LexerContext], tokens: inout TokenList) {
    if case .blockScalar(let parentIndentation) = contexts.last {
      let indentation = line.skippingSpaces(from: 0)
      // Blank lines belong to the block scalar, whatever their indentation.
      if indentation == line.count { return }
      if indentation > parentIndentation {
        tokens.add(indentation..<line.count, .string)
        return
      }
      contexts.removeLast()
    }
    var position = 0
    var atScalarStart = true
    var afterString = false
    if case .string(let rule, let delimiter) = contexts.last {
      position = continueString(
        rule, delimiter: delimiter, in: line, from: 0, contexts: &contexts, tokens: &tokens)
      atScalarStart = false
      afterString = true
    }
    var structure = LineStructure()
    var blockScalarParent: Int?
    while position < line.count {
      let byte = line[position]
      if byte.isSpaceOrTab {
        position += 1
        continue
      }
      if startsComment(line, at: position) {
        tokens.add(position..<line.count, .comment)
        break
      }
      if structure.firstItemColumn == nil, byte == sequenceIndicator,
        line.byte(at: position + 1)?.isSpaceOrTab ?? true
      {
        structure.lastIndicatorColumn = position
        position += 1
        continue
      }
      if structure.firstItemColumn == nil { structure.firstItemColumn = position }
      if atScalarStart,
        let end = openString(at: position, in: line, contexts: &contexts, tokens: &tokens)
      {
        position = end
        atScalarStart = false
        afterString = true
        continue
      }
      if Self.flowDelimiters.contains(byte) {
        atScalarStart = Self.scalarStarts.contains(byte)
        afterString = false
        position += 1
        continue
      }
      if isSeparator(line, at: position, afterString: afterString) {
        atScalarStart = true
        afterString = false
        position += 1
        continue
      }
      let end = wordEnd(in: line, from: position)
      if atScalarStart, isWholeScalar(line, endingAt: end) {
        if isBlockScalarIndicator(line, position..<end) {
          blockScalarParent =
            structure.firstItemColumn == position
            ? structure.lastIndicatorColumn ?? -1 : structure.firstItemColumn
        } else if keywords.contains(position..<end, in: line) {
          tokens.add(position..<end, .keyword)
        } else if Self.isNumeric(line, position..<end) {
          tokens.add(position..<end, .number)
        }
      }
      atScalarStart = false
      afterString = false
      position = end
    }
    if let blockScalarParent, contexts.isEmpty {
      contexts.append(.blockScalar(parentIndentation: blockScalarParent))
    }
  }

  /// Opens a string at a position, if one starts there, and lexes it as far as the line goes.
  private func openString(
    at position: Int, in line: LineBytes, contexts: inout [LexerContext],
    tokens: inout TokenList
  ) -> Int? {
    for (rule, string) in strings.enumerated() {
      guard let opening = string.opening(in: line, at: position) else { continue }
      contexts.append(.string(rule: rule, delimiter: opening.delimiter))
      tokens.add(position..<opening.contentStart, .string)
      return continueString(
        rule, delimiter: opening.delimiter, in: line, from: opening.contentStart,
        contexts: &contexts, tokens: &tokens)
    }
    return nil
  }

  private func continueString(
    _ rule: Int, delimiter: [UInt8], in line: LineBytes, from start: Int,
    contexts: inout [LexerContext], tokens: inout TokenList
  ) -> Int {
    switch strings[rule].scanContent(in: line, from: start, delimiter: delimiter) {
    case .closed(let end):
      contexts.removeLast()
      tokens.add(start..<end, .string)
      return end
    case .lineEnd:
      if !strings[rule].spansLines { contexts.removeLast() }
      tokens.add(start..<line.count, .string)
      return line.count
    case .interpolation:
      preconditionFailure("Strings in data have no interpolations")
    }
  }

  private func startsComment(_ line: LineBytes, at position: Int) -> Bool {
    guard lineComments.contains(where: { line.hasPrefix($0, at: position) }) else {
      return false
    }
    return !commentsNeedPrecedingSpace || position == 0 || line[position - 1].isSpaceOrTab
  }

  private func isSeparator(_ line: LineBytes, at position: Int, afterString: Bool) -> Bool {
    guard line[position] == separator else { return false }
    return !separatorNeedsSpace || afterString
      || (line.byte(at: position + 1)?.isSpaceOrTab ?? true)
  }

  /// The end of a plain word: at a space, flow punctuation, a separator or a comment.
  private func wordEnd(in line: LineBytes, from start: Int) -> Int {
    var position = start + 1
    while let byte = line.byte(at: position), !byte.isSpaceOrTab,
      !Self.flowDelimiters.contains(byte), !isSeparator(line, at: position, afterString: false),
      commentsNeedPrecedingSpace || !startsComment(line, at: position)
    {
      position += 1
    }
    return position
  }

  /// Whether nothing but spaces stands between a word and the end of its scalar.
  private func isWholeScalar(_ line: LineBytes, endingAt end: Int) -> Bool {
    let next = line.skippingSpaces(from: end)
    guard let byte = line.byte(at: next) else { return true }
    return startsComment(line, at: next) || Self.scalarEnds.contains(byte)
      || isSeparator(line, at: next, afterString: false)
  }

  private func isBlockScalarIndicator(_ line: LineBytes, _ word: Range<Int>) -> Bool {
    guard blockScalarIndicators.contains(line[word.lowerBound]) else { return false }
    return word.dropFirst().allSatisfy { Self.blockScalarModifiers.contains(line[$0]) }
  }

  /// Whether a word starts like a number, such as `-1`, `.5`, `0x1F` or a date.
  private static func isNumeric(_ line: LineBytes, _ word: Range<Int>) -> Bool {
    var position = word.lowerBound
    if line[position] == UInt8(ascii: "-") || line[position] == UInt8(ascii: "+") {
      position += 1
    }
    if position < word.upperBound, line[position] == UInt8(ascii: ".") { position += 1 }
    return position < word.upperBound && line[position].isASCIIDigit
  }
}
