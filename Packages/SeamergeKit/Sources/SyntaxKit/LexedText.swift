/// The tokens of every line of a text, kept current as lines change.
///
/// The text itself stays with the caller: the initializer and `replaceLines(in:withLineCount:text:)`
/// read the lines they need and keep only tokens and the state at the end of each line. After
/// a change, lexing goes on past the changed lines only until a line ends in the same state as
/// before, so typing usually costs one line.
package struct LexedText: Sendable {
  private let lexer: Lexer
  private var lines: [LexedLine]

  /// Lexes a text given as its lines.
  ///
  /// - Parameters:
  ///   - language: The language of the text; `LanguageDescription.plainText` yields no
  ///     tokens.
  ///   - lines: The lines of the text. A line may end in its line break.
  package init<Lines: Sequence>(language: LanguageDescription, lines: Lines)
  where Lines.Element: StringProtocol {
    lexer = Lexer(language: language)
    var lexedLines: [LexedLine] = []
    lexedLines.reserveCapacity(lines.underestimatedCount)
    var state = LexerState.initial
    for line in lines {
      let lexed = lexer.lex(line, from: state)
      lexedLines.append(lexed)
      state = lexed.endState
    }
    self.lines = lexedLines
  }

  /// The number of lines.
  package var lineCount: Int { lines.count }

  /// The tokens of a line, in order and without overlap, in UTF-16 offsets from the start of
  /// the line.
  ///
  /// - Precondition: `line` lies within `0..<lineCount`.
  package func tokens(inLine line: Int) -> [SyntaxToken] {
    precondition(lines.indices.contains(line), "Line \(line) is out of range")
    return lines[line].tokens
  }

  /// Replaces a range of lines with new lines and lexes again as far as the change reaches.
  ///
  /// - Parameters:
  ///   - range: The lines that were replaced, in the text before the change.
  ///   - lineCount: The number of lines that took their place.
  ///   - text: The line at an index of the text after the change. It is asked for the new
  ///     lines and for as many following lines as the change reaches.
  /// - Returns: The lines whose tokens were lexed again, in the text after the change. Tokens
  ///   of the other lines are unchanged.
  /// - Precondition: `range` lies within `0...lineCount`.
  @discardableResult
  package mutating func replaceLines<Line: StringProtocol>(
    in range: Range<Int>, withLineCount lineCount: Int, text: (Int) -> Line
  ) -> Range<Int> {
    precondition(
      range.lowerBound >= 0 && range.upperBound <= lines.count, "Lines \(range) are out of range")
    precondition(lineCount >= 0, "The number of new lines must not be negative")
    let start = range.lowerBound
    // The state the first line after the change was lexed from before the change.
    var previousState = range.upperBound == 0 ? .initial : lines[range.upperBound - 1].endState
    var state = start == 0 ? .initial : lines[start - 1].endState
    var newLines: [LexedLine] = []
    newLines.reserveCapacity(lineCount)
    for offset in 0..<lineCount {
      let lexed = lexer.lex(text(start + offset), from: state)
      newLines.append(lexed)
      state = lexed.endState
    }
    lines.replaceSubrange(range, with: newLines)
    var end = start + lineCount
    while end < lines.count, state != previousState {
      previousState = lines[end].endState
      lines[end] = lexer.lex(text(end), from: state)
      state = lines[end].endState
      end += 1
    }
    return start..<end
  }
}
