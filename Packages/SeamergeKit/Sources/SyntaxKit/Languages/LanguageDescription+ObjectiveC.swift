extension LanguageDescription {
  /// Objective-C, which also covers headers and Objective-C++; its directives such as
  /// `@interface` and `#import` are keywords.
  static let objectiveC = LanguageDescription(
    name: "Objective-C", fileExtensions: ["m", "mm", "h"],
    syntax: .code(
      CodeSyntax(
        keywords: cKeywords + [
          "BOOL", "Class", "id", "IMP", "instancetype", "nil", "Nil", "NO", "nonnull",
          "nullable", "SEL", "self", "super", "YES", "_Nonnull", "_Nullable", "__autoreleasing",
          "__block", "__bridge", "__bridge_retained", "__bridge_transfer", "__kindof",
          "__strong", "__unsafe_unretained", "__weak",
        ],
        lineComments: ["//"],
        blockComments: [BlockCommentSyntax(open: "/*", close: "*/")],
        strings: [
          StringSyntax("\"", prefixes: ["", "@", "L", "u", "U", "u8"]),
          StringSyntax("'", prefixes: ["", "L", "u", "U", "u8"]),
        ],
        keywordPrefixes: "@#")))
}
