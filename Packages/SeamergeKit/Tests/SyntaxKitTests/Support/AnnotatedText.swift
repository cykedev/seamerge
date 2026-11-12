import SyntaxKit

/// Text with its tokens written into it, such as `«k:let» x = «n:1»`.
///
/// A token is `«`, the first letter of its kind, a colon, its text and `»`. A token that
/// spans lines is written once per line. Samples state their expected tokens this way, and the
/// lexed result is written the same way for comparison, so a failing test shows the
/// difference as text.
enum AnnotatedText {
  /// The text without its token marks, split into lines.
  static func plainLines(of annotated: String) -> [String] {
    var plain = ""
    var characters = annotated.makeIterator()
    while let character = characters.next() {
      switch character {
      case "«":
        // Skip the kind letter and the colon.
        _ = characters.next()
        _ = characters.next()
      case "»":
        continue
      default:
        plain.append(character)
      }
    }
    return lines(of: plain)
  }

  /// The lines of a text, split at line feeds and without them.
  static func lines(of text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  }

  /// The lines with the tokens a lexed text found in them written into them.
  static func annotatedLines(_ lines: [String], lexed: LexedText) -> [String] {
    lines.indices.map { index in
      let utf16 = Array(lines[index].utf16)
      var annotated = ""
      var position = 0
      func append(_ range: Range<Int>) {
        annotated += String(decoding: utf16[range], as: UTF16.self)
      }
      for token in lexed.tokens(inLine: index) {
        append(position..<token.range.lowerBound)
        annotated += "«\(mark(of: token.kind)):"
        append(token.range)
        annotated += "»"
        position = token.range.upperBound
      }
      append(position..<utf16.count)
      return annotated
    }
  }

  private static func mark(of kind: TokenKind) -> Character {
    switch kind {
    case .comment: "c"
    case .string: "s"
    case .number: "n"
    case .keyword: "k"
    }
  }
}
