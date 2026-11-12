extension LanguageSample {
  static let json = LanguageSample(
    language: "JSON", fileName: "package.json",
    annotated: ###"""
      {
        «s:"name"»: «s:"demo"»,
        «s:"version"»: «s:"1.2.3"»,
        «s:"private"»: «k:true»,
        «s:"count"»: «n:-12.5e3»,
        «s:"nothing"»: «k:null»,
        «s:"list"»: [«n:1», «s:"two"», «k:false»],
        «s:"url"»: «s:"https://example.com/a//b"»
      }
      """###)
}
