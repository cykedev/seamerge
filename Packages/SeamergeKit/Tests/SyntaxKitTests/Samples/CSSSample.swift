extension LanguageSample {
  static let css = LanguageSample(
    language: "CSS", fileName: "style.css",
    annotated: ###"""
      «k:@import» url(«s:"theme.css"»);

      «c:/* Layout */»
      .box > a:hover {
        margin: «n:0» auto;
        width: calc(«n:100»% - «n:2.5em»);
        color: #fff «k:!important»;
        font-family: «s:"Helvetica Neue"», sans-serif;
      }
      «k:@media» (max-width: «n:600px») «k:and» (prefers-color-scheme: dark) {
        .box { display: none; }
      }
      """###)
}
