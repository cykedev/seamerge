extension LanguageSample {
  static let rust = LanguageSample(
    language: "Rust", fileName: "lib.rs",
    annotated: ###"""
      «c:/* Outer /* nested */ comment */»
      «k:pub» «k:fn» longest<'a>(x: &'a str, y: &'a str) -> &'a str {
          «k:let» raw = «s:r#"raw "string" with \ backslash"#»;
          «k:let» bytes = «s:b"bytes\n"»;
          «k:let» c = «s:'c'»;
          «k:let» escaped = «s:'\''»;
          «k:let» n = «n:1_000u32» + «n:0xFFi64» + «n:2.5e10f64»;
          «k:if» x.len() > y.len() { x } «k:else» { y } «c:// longest»
      }
      """###)
}
