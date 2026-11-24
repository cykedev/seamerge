import PaneKit
import SyntaxKit
import TextBasics

/// The tokens of one text, lexed by its syntax, as a pane asks for them line by line.
///
/// A pane asks by the number it gives a row, which for a side of a patch is the number its
/// hunks give the line rather than its place in the text; the tokens take it back to the line.
@MainActor
final class SyntaxTokens: PaneSyntaxProvider {
  /// The tokens of the lines of the text.
  var lexed: LexedText

  /// The number each line of the text has, in ascending order, where the text is a side of a
  /// patch; `nil` where the lines are numbered by their place.
  private let lineNumbers: [Int32]?

  /// Supplies the tokens of `lexed`, whose lines have `lineNumbers` where they are not numbered
  /// by their place.
  init(_ lexed: LexedText, lineNumbers: [Int32]? = nil) {
    self.lexed = lexed
    self.lineNumbers = lineNumbers
  }

  func tokens(inLine number: Int) -> [PaneToken] {
    guard let lineNumbers else { return tokens(inTextLine: number) }
    let line = lineNumbers.partitioningIndex { Int($0) >= number }
    guard line < lineNumbers.count, lineNumbers[line] == number else { return [] }
    return tokens(inTextLine: line)
  }

  /// The tokens of `line`, counted from 0 in the text.
  func tokens(inTextLine line: Int) -> [PaneToken] {
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
