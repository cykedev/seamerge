extension LanguageSample {
  static let markdown = LanguageSample(
    language: "Markdown", fileName: "README.md",
    annotated: ###"""
      «k:# Seamerge»

      Some *text* with «s:`inline code`» and «s:``code with ` backtick``».
      An unmatched ` backtick stays text.

      «c:<!-- A comment»
      «c:spanning lines -->»

      «s:```swift»
      «s:let x = "not lexed as Swift"»
      «s:```»

      «k:## Heading two»
      «s:~~~»
      «s:tilde fence»
      «s:~~~»
      ####### not a heading
      """###)
}
