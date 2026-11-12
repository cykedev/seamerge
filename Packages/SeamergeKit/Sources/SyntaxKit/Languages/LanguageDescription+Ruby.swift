extension LanguageDescription {
  /// Ruby, with interpolation, here documents and `=begin` comments.
  static let ruby = LanguageDescription(
    name: "Ruby", fileExtensions: ["rb", "rake", "gemspec", "ru"],
    fileNames: ["Gemfile", "Rakefile", "Podfile", "Fastfile", "Brewfile", "Guardfile"],
    interpreters: ["ruby"],
    syntax: .code(
      CodeSyntax(
        keywords: [
          "__FILE__", "__LINE__", "__method__", "alias", "and", "begin", "BEGIN", "break",
          "case", "class", "def", "defined", "do", "else", "elsif", "end", "END", "ensure",
          "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue",
          "retry", "return", "self", "super", "then", "true", "undef", "unless", "until",
          "when", "while", "yield",
        ],
        lineComments: ["#"],
        blockComments: [
          BlockCommentSyntax(open: "=begin", close: "=end", standsOnOwnLines: true)
        ],
        strings: [
          StringSyntax(
            "\"", spansLines: true,
            interpolations: [StringSyntax.Interpolation(open: "#{", close: "}")]),
          StringSyntax("'", spansLines: true),
          StringSyntax(
            "`", spansLines: true,
            interpolations: [StringSyntax.Interpolation(open: "#{", close: "}")]),
        ],
        hereDocuments: HereDocumentSyntax(
          introducers: ["<<~", "<<-", "<<"], allowsSpaceBeforeWord: false),
        variablePrefixes: "@$")))
}
