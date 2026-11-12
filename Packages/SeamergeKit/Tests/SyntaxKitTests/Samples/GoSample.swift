extension LanguageSample {
  static let go = LanguageSample(
    language: "Go", fileName: "main.go",
    annotated: ###"""
      «k:package» main

      «k:import» «s:"fmt"»

      «c:/* Package comment */»
      «k:func» main() {
      	raw := «s:`raw string with "quotes"»
      «s:spanning lines`»
      	r := «s:'x'»
      	n := «n:0x1F» + «n:1_000» + «n:3.5»
      	fmt.Println(raw, r, n, «k:nil») «c:// done»
      }
      """###)
}
