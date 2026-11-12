extension LanguageSample {
  static let typeScript = LanguageSample(
    language: "TypeScript", fileName: "example.ts",
    annotated: ###"""
      «k:interface» Shape {
        «k:readonly» kind: «s:"circle"» | «s:"square"»;
        area(): «k:number»;
      }

      type Point = { x: «k:number»; y: «k:number» };

      «k:export» «k:class» Circle «k:implements» Shape {
        «k:readonly» kind = «s:"circle"» «k:as» «k:const»;
        constructor(«k:private» radius: «k:number») {}
        area(): «k:number» { «k:return» Math.PI * «k:this».radius ** «n:2»; } «c:// square units»
      }
      «k:const» view = <Circle radius={«n:2»} />;
      """###)
}
