extension LanguageSample {
  static let toml = LanguageSample(
    language: "TOML", fileName: "Cargo.toml",
    annotated: ###"""
      «c:# Package»
      [package]
      name = «s:"demo"»
      version = «s:"0.1.0"»
      edition = «n:2024»
      published = «n:1979-05-27T07:32:00Z»
      ratio = «k:+inf»

      [dependencies]
      serde = { version = «s:"1.0"», features = [«s:"derive"»] }
      notes = «s:"""»
      «s:Multi-line "basic" string»
      «s:"""»
      path = «s:'C:\literal'»
      """###)
}
