/// What is still open at the end of a line: a comment, a string, a tag and the like.
///
/// The state is a stack, because constructs nest: an interpolation sits inside a string, and
/// a string may sit inside the interpolation. Lexing a line from equal states gives equal
/// results, which is what lets lexing stop once a changed line ends in its old state.
struct LexerState: Sendable, Hashable {
  /// The state at the start of a text, with nothing open.
  static let initial = LexerState(contexts: [])

  /// The open constructs, innermost last.
  var contexts: [LexerContext]
}

/// One construct that is open at the end of a line.
///
/// Each lexer family uses its own cases; rule numbers refer to the list of comment or string
/// forms in the language’s syntax.
enum LexerContext: Sendable, Hashable {
  /// A block comment; `depth` counts the nested comments inside the outermost one.
  case blockComment(rule: Int, depth: Int)

  /// A string; `delimiter` is the extra delimiter of a raw string, otherwise empty.
  case string(rule: Int, delimiter: [UInt8])

  /// Code inside a string, ended by `close`; `depth` counts the brackets of its kind that are
  /// open within the code.
  case interpolation(close: UInt8, depth: Int)

  /// The lines of a here document, up to the line holding `terminator`.
  case hereDocument(terminator: [UInt8])

  /// A markup comment.
  case markupComment

  /// A section of character data.
  case characterData

  /// The inside of a tag, after its name; `rawTextElement` is set when the tag opens an
  /// element whose content is not markup.
  case tag(rawTextElement: Int?)

  /// A quoted attribute value inside a tag.
  case attributeValue(quote: UInt8)

  /// The content of an element that is not markup, up to its closing tag.
  case rawText(element: Int)

  /// A fenced block of code, up to a fence of at least `length` of the same `marker`.
  case fencedCode(marker: UInt8, length: Int)

  /// A block scalar, made of the lines indented further than `parentIndentation`.
  case blockScalar(parentIndentation: Int)
}
