extension LanguageSample {
  static let xml = LanguageSample(
    language: "XML", fileName: "Info.plist",
    annotated: ###"""
      <?«k:xml» version=«s:"1.0"» encoding=«s:"UTF-8"»?>
      <«k:plist» version=«s:"1.0"»>
      <«k:dict»>
        <«k:key»>Name</«k:key»>
        <«k:string»>«s:<![CDATA[a < b]]>»</«k:string»>
        «c:<!-- comment -->»
        <«k:integer»>42</«k:integer»>
      </«k:dict»>
      </«k:plist»>
      """###)
}
