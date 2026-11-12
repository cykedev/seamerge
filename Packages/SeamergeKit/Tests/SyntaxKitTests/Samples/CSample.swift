extension LanguageSample {
  static let c = LanguageSample(
    language: "C", fileName: "example.c",
    annotated: ###"""
      «k:#include» <stdio.h>
      «k:#define» LIMIT «n:10UL»

      «c:/* Multi-line»
      «c:   comment */»
      «k:int» main(«k:void») {
        «k:char» c = «s:'\''»;
        «k:const» «k:char» *s = «s:"tab\t \"quoted\" /* not a comment */"»;
        «k:for» («k:int» i = «n:0»; i < LIMIT; i++) { printf(«s:"%d\n"», i); }
        «k:return» «k:sizeof»(«s:L"wide"») + «s:u8"utf8"»[«n:0»] + «n:1.5f»;
      }
      """###)
}
