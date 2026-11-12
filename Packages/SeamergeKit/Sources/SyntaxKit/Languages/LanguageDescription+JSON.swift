extension LanguageDescription {
  /// JSON, which also takes the line comments of JSON with comments.
  static let json = LanguageDescription(
    name: "JSON",
    fileExtensions: ["json", "jsonc", "geojson", "xcstrings", "resolved", "webmanifest"],
    syntax: .data(
      DataSyntax(
        keywords: ["true", "false", "null"],
        lineComments: ["//"],
        commentsNeedPrecedingSpace: false,
        strings: [StringSyntax("\"")],
        keyValueSeparator: ":",
        separatorNeedsSpace: true,
        sequenceIndicator: nil,
        blockScalarIndicators: [])))
}
