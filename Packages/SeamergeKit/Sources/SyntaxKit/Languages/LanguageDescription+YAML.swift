extension LanguageDescription {
  /// YAML, with block scalars and the literal values of YAML 1.1 and 1.2.
  static let yaml = LanguageDescription(
    name: "YAML", fileExtensions: ["yml", "yaml"],
    syntax: .data(
      DataSyntax(
        keywords: [
          "true", "True", "TRUE", "false", "False", "FALSE", "yes", "Yes", "YES", "no", "No",
          "NO", "on", "On", "ON", "off", "Off", "OFF", "null", "Null", "NULL", "~",
        ],
        lineComments: ["#"],
        commentsNeedPrecedingSpace: true,
        strings: [
          StringSyntax("\"", spansLines: true),
          StringSyntax("'", escape: .doubledDelimiter, spansLines: true),
        ],
        keyValueSeparator: ":",
        separatorNeedsSpace: true,
        sequenceIndicator: "-",
        blockScalarIndicators: ["|", ">"])))
}
