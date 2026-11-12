extension LanguageSample {
  static let javaScript = LanguageSample(
    language: "JavaScript", fileName: "example.js",
    annotated: ###"""
      «c:// @ts-check»
      «k:import» { readFile } «k:from» «s:"node:fs/promises"»;

      «k:const» greeting = «s:`Hello, ${»user.name ?? «s:"guest"}!»
      «s:Second line of the template ${`nested ${»«n:1» + «n:2»«s:}`}`»;
      «k:const» $el = document.querySelector(«s:'#app'»); «c:/* jQuery-style name */»
      «k:export» «k:async» «k:function» load(path) {
        «k:const» text = «k:await» readFile(path, «s:'utf8'»);
        «k:return» text.length > «n:0x10» ? «k:null» : «k:undefined»;
      }
      «k:const» element = <div className=«s:"box"»>Text</div>;
      """###)
}
