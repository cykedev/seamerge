extension LanguageDescription {
  /// XML, including property lists and Interface Builder files.
  static let xml = LanguageDescription(
    name: "XML",
    fileExtensions: [
      "xml", "plist", "xib", "storyboard", "svg", "xsd", "xsl", "xslt", "entitlements",
      "xcscheme", "xcworkspacedata", "resx", "csproj", "props", "targets",
    ],
    syntax: .markup(
      MarkupSyntax(
        comment: Delimiters(open: "<!--", close: "-->"),
        tags: TagSyntax(
          characterData: Delimiters(open: "<![CDATA[", close: "]]>"), rawTextElements: []),
        lightweight: nil)))
}
