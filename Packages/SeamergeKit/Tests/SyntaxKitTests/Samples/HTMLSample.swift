extension LanguageSample {
  static let html = LanguageSample(
    language: "HTML", fileName: "index.html",
    annotated: ###"""
      <!«k:DOCTYPE» html>
      <«k:html» lang=«s:"en"»>
      <«k:head»>
        «c:<!-- A comment»
      «c:       spanning lines -->»
        <«k:style»>p > a { color: red; }</«k:style»>
        <«k:script»>if (a < b && c > d) { run("</div>"); }</«k:script»>
      </«k:head»>
      <«k:body» class=«s:"main"» data-note=«s:'single»
      «s:quoted'»>
        <«k:p»>Text &amp; more</«k:p»>
        <«k:img» src=«s:"logo.png"» alt=«s:"Logo"»/>
      </«k:body»>
      </«k:html»>
      """###)
}
