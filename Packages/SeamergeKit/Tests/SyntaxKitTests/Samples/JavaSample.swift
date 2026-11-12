extension LanguageSample {
  static let java = LanguageSample(
    language: "Java", fileName: "Example.java",
    annotated: ###"""
      «k:package» demo;

      «c:/** Documentation comment. */»
      «k:public» «k:final» «k:class» Greeter {
        «k:private» «k:static» «k:final» «k:long» MAX = «n:10_000L»;

        @Override
        «k:public» String toString() {
          String block = «s:"""»
      «s:        Hello, "world" // not a comment»
      «s:        """»;
          «k:return» block + «s:'c'» + MAX + «n:0x1p3»;
        }
      }
      """###)
}
