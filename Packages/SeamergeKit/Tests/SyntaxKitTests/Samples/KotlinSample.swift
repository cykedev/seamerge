extension LanguageSample {
  static let kotlin = LanguageSample(
    language: "Kotlin", fileName: "Example.kt",
    annotated: ###"""
      «k:package» demo

      «c:/* Outer /* inner */ still a comment */»
      «k:data» «k:class» Point(«k:val» x: Int, «k:val» y: Int = «n:0»)

      «k:fun» describe(p: Point?): String {
        «k:val» raw = «s:"""Raw \n with ${»p?.x ?: «s:"none"} and "quotes""""»
        «k:return» «s:"Point(${»p?.x«s:}, ${»«k:if» (p == «k:null») «s:"?"» «k:else» «s:"${»p.y«s:}"})"»
      }
      """###)
}
