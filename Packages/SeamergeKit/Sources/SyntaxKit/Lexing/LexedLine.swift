/// The result of lexing one line: its tokens and the state at its end.
struct LexedLine: Sendable, Hashable {
  /// The tokens, in order and without overlap.
  let tokens: [SyntaxToken]

  /// The state the next line starts in.
  let endState: LexerState
}
