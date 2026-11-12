extension LanguageDescription {
  /// Shell scripts for sh, Bash and Zsh, with here documents and command substitution in
  /// strings.
  static let shell = LanguageDescription(
    name: "Shell", fileExtensions: ["sh", "bash", "zsh", "ksh", "command"],
    fileNames: [".bashrc", ".bash_profile", ".profile", ".zshrc", ".zprofile", ".zshenv"],
    interpreters: ["sh", "bash", "zsh", "ksh", "dash"],
    syntax: .code(
      CodeSyntax(
        keywords: [
          "break", "case", "continue", "declare", "do", "done", "elif", "else", "esac", "exit",
          "export", "fi", "for", "function", "if", "in", "local", "readonly", "return",
          "select", "then", "typeset", "unset", "until", "while",
        ],
        lineComments: ["#"],
        lineCommentsStartWords: true,
        strings: [
          StringSyntax(
            "\"", spansLines: true,
            interpolations: [
              StringSyntax.Interpolation(open: "$(", close: ")"),
              StringSyntax.Interpolation(open: "${", close: "}"),
            ]),
          StringSyntax("'", prefixes: ["$"], spansLines: true),
          StringSyntax("'", escape: .noEscapes, spansLines: true),
          StringSyntax("`", spansLines: true),
        ],
        hereDocuments: HereDocumentSyntax(
          introducers: ["<<-", "<<"], allowsSpaceBeforeWord: true),
        variablePrefixes: "$",
        wordCharacters: "-")))
}
