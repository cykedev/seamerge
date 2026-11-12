extension LanguageDescription {
  /// TOML, with multi-line basic and literal strings.
  static let toml = LanguageDescription(
    name: "TOML", fileExtensions: ["toml"], fileNames: ["Cargo.lock"],
    syntax: .data(
      DataSyntax(
        keywords: ["true", "false", "inf", "+inf", "-inf", "nan", "+nan", "-nan"],
        lineComments: ["#"],
        commentsNeedPrecedingSpace: false,
        strings: [
          StringSyntax("\"\"\"", spansLines: true),
          StringSyntax("'''", escape: .noEscapes, spansLines: true),
          StringSyntax("\""),
          StringSyntax("'", escape: .noEscapes),
        ],
        keyValueSeparator: "=",
        separatorNeedsSpace: false,
        sequenceIndicator: nil,
        blockScalarIndicators: [])))
}
