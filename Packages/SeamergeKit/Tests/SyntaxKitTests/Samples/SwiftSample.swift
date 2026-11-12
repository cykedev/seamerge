extension LanguageSample {
  static let swift = LanguageSample(
    language: "Swift", fileName: "Example.swift",
    annotated: ###"""
      «k:import» Foundation

      «c:/* A block comment /* with a nested one */ still open»
      «c:   until here */» «k:let» afterComment = «n:1»
      «c:// A line comment with "quotes" and /* an opener»
      «k:@MainActor» «k:final» «k:class» Greeter: Sendable {
        «k:let» name = «s:"Ada // not a comment"»
        «k:let» path = «s:#"C:\Users\"#»
        «k:let» hashes = «s:##"a "# quote"##» + «s:"tail"»
        «k:let» message = «s:"Hello, \(»name.uppercased(with: «s:"en"»)«s:) and \(»count + «n:1»«s:)!"»
        «k:let» escaped = «s:"a \"quoted\" \\ word"»
        «k:let» numbers = [«n:0x1F», «n:0b1010», «n:1_000_000», «n:3.14», «n:2.5e-3», «n:.5»]
        «k:let» range = «n:1»...«n:5»

        «k:func» poem() -> String {
          «s:"""»
      «s:    First line with "quotes" and \(»name«s:)»
      «s:    Second line with \""" escaped and "" two quotes»
      «s:    """»
        }

        «k:var» raw: String {
          «s:#"""»
      «s:    Raw \(not interpolated) but \#(»name«s:) is»
      «s:    """#»
        }
        «k:#if» DEBUG
        «k:let» flag = «k:true»
        «k:#endif»
      }
      «k:let» café = «k:nil» ?? «s:"ok"»
      """###)
}
