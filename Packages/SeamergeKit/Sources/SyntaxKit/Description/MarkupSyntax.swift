/// The syntax of a markup language, as read by the lexer for markup.
///
/// Tag languages such as HTML and XML color tag names as keywords and attribute values as
/// strings. Lightweight markup such as Markdown colors headings as keywords and code as
/// strings.
struct MarkupSyntax: Sendable, Hashable {
  /// The delimiters of a comment.
  let comment: Delimiters

  /// The rules for tags, in a tag language.
  let tags: TagSyntax?

  /// The rules for headings and code, in lightweight markup.
  let lightweight: LightweightMarkupSyntax?
}

/// An opening and a closing delimiter.
struct Delimiters: Sendable, Hashable {
  /// The opening delimiter.
  let open: String

  /// The closing delimiter.
  let close: String
}

/// How tags are written in a tag language.
struct TagSyntax: Sendable, Hashable {
  /// The delimiters of a section of character data, which is colored as a string.
  let characterData: Delimiters?

  /// The elements whose content is not markup, such as `script` in HTML; their names match
  /// regardless of case.
  let rawTextElements: [String]
}

/// How headings and code are written in lightweight markup.
struct LightweightMarkupSyntax: Sendable, Hashable {
  /// The character that starts a heading when it begins a line, up to six times and followed
  /// by a space.
  let headingMarker: Character

  /// The characters of which three or more on a line of their own fence a block of code.
  let codeFenceMarkers: [Character]

  /// The character that encloses code within a line; a run of it is closed by a run of the
  /// same length.
  let codeSpanMarker: Character
}
