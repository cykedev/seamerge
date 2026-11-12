extension LanguageSample {
  static let scss = LanguageSample(
    language: "SCSS", fileName: "theme.scss",
    annotated: ###"""
      «c:// Variables»
      $primary: #333 «k:!default»;

      «k:@mixin» rounded($radius: «n:4px») {
        border-radius: $radius;
      }

      .card {
        «k:@include» rounded(«n:8px»);
        content: «s:'quoted'»;
        «c:/* block comment */»
      }
      """###)
}
