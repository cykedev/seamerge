extension LanguageDescription {
  /// TypeScript, including TSX.
  static let typeScript = LanguageDescription(
    name: "TypeScript", fileExtensions: ["ts", "mts", "cts", "tsx"],
    interpreters: ["ts-node", "deno", "bun"],
    syntax: .code(
      javaScriptSyntax(
        keywords: javaScriptKeywords + [
          "abstract", "accessor", "any", "as", "asserts", "bigint", "boolean", "declare",
          "enum", "implements", "infer", "interface", "is", "keyof", "namespace", "never",
          "number", "object", "override", "private", "protected", "public", "readonly",
          "satisfies", "string", "symbol", "unique", "unknown",
        ])))
}
