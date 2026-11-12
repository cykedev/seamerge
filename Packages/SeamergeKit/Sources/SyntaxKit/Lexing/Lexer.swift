/// Splits the lines of one language into tokens.
///
/// The result of a line depends only on its text and the state at the end of the line before,
/// so a text can be lexed again from any line on.
struct Lexer: Sendable {
  private enum Family: Sendable {
    case code(CodeLexer)
    case markup(MarkupLexer)
    case data(DataLexer)
    case plainText
  }

  private let family: Family

  init(language: LanguageDescription) {
    family =
      switch language.syntax {
      case .code(let syntax): .code(CodeLexer(syntax))
      case .markup(let syntax): .markup(MarkupLexer(syntax))
      case .data(let syntax): .data(DataLexer(syntax))
      case .plainText: .plainText
      }
  }

  /// Lexes a line, which may end in a line break, starting in the state the line before ended
  /// in.
  ///
  /// - Parameter readCount: A count to which every byte the lexer reads from the line is
  ///   added, the measure of its work.
  func lex<Line: StringProtocol>(
    _ line: Line, from state: LexerState, readCount: UnsafeMutablePointer<Int>? = nil
  ) -> LexedLine {
    if case .plainText = family { return LexedLine(tokens: [], endState: state) }
    if let lexed = line.utf8.withContiguousStorageIfAvailable({
      lex(bytes: $0, from: state, readCount: readCount)
    }) {
      return lexed
    }
    return Array(line.utf8).withUnsafeBufferPointer {
      lex(bytes: $0, from: state, readCount: readCount)
    }
  }

  private func lex(
    bytes: UnsafeBufferPointer<UInt8>, from state: LexerState,
    readCount: UnsafeMutablePointer<Int>?
  ) -> LexedLine {
    let line = LineBytes(bytes, readCount: readCount)
    var contexts = state.contexts
    var tokens = TokenList()
    switch family {
    case .code(let lexer): lexer.lex(line, contexts: &contexts, tokens: &tokens)
    case .markup(let lexer): lexer.lex(line, contexts: &contexts, tokens: &tokens)
    case .data(let lexer): lexer.lex(line, contexts: &contexts, tokens: &tokens)
    case .plainText: break
    }
    return LexedLine(
      tokens: tokens.utf16Tokens(in: bytes), endState: LexerState(contexts: contexts))
  }
}
