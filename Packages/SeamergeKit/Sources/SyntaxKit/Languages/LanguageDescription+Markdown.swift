extension LanguageDescription {
  /// Markdown, with headings, fenced code, code spans and HTML comments.
  static let markdown = LanguageDescription(
    name: "Markdown", fileExtensions: ["md", "markdown", "mdown", "mkd"],
    syntax: .markup(
      MarkupSyntax(
        comment: Delimiters(open: "<!--", close: "-->"),
        tags: nil,
        lightweight: LightweightMarkupSyntax(
          headingMarker: "#", codeFenceMarkers: ["`", "~"], codeSpanMarker: "`"))))
}
