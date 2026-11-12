extension LanguageDescription {
  /// HTML, whose `script` and `style` elements hold no markup.
  static let html = LanguageDescription(
    name: "HTML", fileExtensions: ["html", "htm", "xhtml"],
    syntax: .markup(
      MarkupSyntax(
        comment: Delimiters(open: "<!--", close: "-->"),
        tags: TagSyntax(characterData: nil, rawTextElements: ["script", "style"]),
        lightweight: nil)))
}
