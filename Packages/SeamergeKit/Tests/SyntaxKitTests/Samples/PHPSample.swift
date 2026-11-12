extension LanguageSample {
  static let php = LanguageSample(
    language: "PHP", fileName: "index.php",
    annotated: ###"""
      <?php
      «k:namespace» App;

      «c:// Comment»
      «c:# Another comment»
      «k:final» «k:class» Greeter {
          «k:public» «k:function» greet(string $name): string {
              $message = «s:"Hello, $name"»;
              $text = «s:<<<EOT»
      «s:            Here document with "quotes"»
      «s:            EOT;»
              «k:return» $message . «s:'done'» . «n:42»;
          }
      }
      """###)
}
