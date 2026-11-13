import PaneKit
import SyntaxKit

/// The tokens of one text, lexed by its syntax, as a pane asks for them line by line.
@MainActor
final class SyntaxTokens: PaneSyntaxProvider {
  /// The tokens of the lines of the text.
  var lexed: LexedText

  /// Supplies the tokens of `lexed`.
  init(_ lexed: LexedText) {
    self.lexed = lexed
  }

  func tokens(inLine line: Int) -> [PaneToken] {
    guard line >= 0, line < lexed.lineCount else { return [] }
    return lexed.tokens(inLine: line).map { token in
      PaneToken(range: token.range, kind: PaneToken.Kind(token.kind))
    }
  }
}

extension PaneToken.Kind {
  /// The kind of a pane token for a token of `kind`.
  init(_ kind: TokenKind) {
    switch kind {
    case .keyword: self = .keyword
    case .string: self = .string
    case .number: self = .number
    case .comment: self = .comment
    }
  }
}
