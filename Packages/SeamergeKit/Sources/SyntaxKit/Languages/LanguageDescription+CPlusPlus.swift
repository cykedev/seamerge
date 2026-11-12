extension LanguageDescription {
  /// C++, with raw strings such as `R"(…)"` and `'` as a digit separator.
  static let cPlusPlus = LanguageDescription(
    name: "C++",
    fileExtensions: ["cpp", "cc", "cxx", "c++", "hpp", "hh", "hxx", "h++", "ipp", "tpp", "inl"],
    syntax: .code(
      CodeSyntax(
        keywords: cKeywords + [
          "and", "and_eq", "asm", "bitand", "bitor", "catch", "char8_t", "char16_t",
          "char32_t", "class", "co_await", "co_return", "co_yield", "compl", "concept",
          "consteval", "constinit", "const_cast", "decltype", "delete", "dynamic_cast",
          "explicit", "export", "final", "friend", "import", "module", "mutable", "namespace",
          "new", "noexcept", "not", "not_eq", "operator", "or", "or_eq", "override", "private",
          "protected", "public", "reinterpret_cast", "requires", "static_cast", "template",
          "this", "throw", "try", "typeid", "typename", "using", "virtual", "wchar_t", "xor",
          "xor_eq",
        ],
        lineComments: ["//"],
        blockComments: [BlockCommentSyntax(open: "/*", close: "*/")],
        strings: [
          StringSyntax(
            "\"", prefixes: ["R", "LR", "uR", "UR", "u8R"], escape: .noEscapes,
            spansLines: true, rawDelimiter: .parenthesized)
        ] + cStrings,
        keywordPrefixes: "#",
        digitSeparators: "'")))
}
