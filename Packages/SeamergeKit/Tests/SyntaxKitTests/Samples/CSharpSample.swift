extension LanguageSample {
  static let cSharp = LanguageSample(
    language: "C#", fileName: "Example.cs",
    annotated: ###"""
      «k:#region» Demo
      «k:using» System;

      «k:namespace» Demo;

      «k:public» «k:sealed» «k:record» Greeter(«k:string» Name)
      {
          «k:public» «k:string» Path => «s:@"C:\Users\""quoted"""»;
          «k:public» «k:string» Greet(«k:int» count) => «s:$"Hello, {»Name«s:} x{»count + «n:1»«s:} {{literal}}"»;
          «k:public» «k:string» Raw => «s:"""»
      «s:        Raw "text" with \n»
      «s:        """»;
          «k:public» «k:string» Both => «s:$@"{»Name«s:}\ and ""more"""»;
          «k:char» C = «s:'x'»; «k:double» D = «n:1.5e3»;
      }
      «k:#endregion»
      """###)
}
