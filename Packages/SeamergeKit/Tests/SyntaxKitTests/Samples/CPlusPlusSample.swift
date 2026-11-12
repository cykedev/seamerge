extension LanguageSample {
  static let cPlusPlus = LanguageSample(
    language: "C++", fileName: "example.cpp",
    annotated: ###"""
      «k:#include» <string>

      «k:namespace» demo {
      «k:template» <«k:typename» T> «k:class» Box «k:final» {
       «k:public»:
        «k:auto» raw() «k:const» { «k:return» «s:R"sql(SELECT "a" FROM t -- )" not the end»
      «s:)sql"»; }
        «k:static» «k:constexpr» «k:long» big = «n:1'000'000»;
        «k:bool» empty() «k:const» «k:noexcept» { «k:return» value == «k:nullptr»; }
       «k:private»:
        T* value = «k:nullptr»;  «c:// owned elsewhere»
      };
      }  «c:// namespace demo»
      """###)
}
