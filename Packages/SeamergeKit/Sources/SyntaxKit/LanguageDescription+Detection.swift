extension LanguageDescription {
  /// Every language SyntaxKit describes, apart from plain text.
  package static let all: [LanguageDescription] = [
    .swift, .objectiveC, .c, .cPlusPlus, .java, .kotlin, .cSharp, .javaScript, .typeScript,
    .python, .ruby, .go, .rust, .php, .shell, .sql, .html, .xml, .css, .scss, .json, .yaml,
    .toml, .markdown,
  ]

  /// The longest part of a first line read for an interpreter, so that a long first line costs
  /// no more than a short one.
  private static let maximumShebangLength = 256

  /// The language of a file, recognized by its name and, failing that, by the interpreter its
  /// first line names after `#!`.
  ///
  /// - Parameters:
  ///   - fileName: The name of the file, with or without its folder.
  ///   - firstLine: The first line of the file, or the empty string if it is not known.
  /// - Returns: The language, or `plainText` if neither name nor first line is recognized.
  package init(fileName: String, firstLine: String = "") {
    self = Self.language(fileName: fileName, firstLine: firstLine) ?? .plainText
  }

  private static func language(fileName: String, firstLine: String) -> LanguageDescription? {
    let name = fileName.split(separator: "/").last.map(String.init) ?? fileName
    if let language = all.first(where: { $0.fileNames.contains(name) }) { return language }
    if let dot = name.lastIndex(of: "."), dot != name.startIndex {
      let fileExtension = name[name.index(after: dot)...].lowercased()
      if let language = all.first(where: { $0.fileExtensions.contains(fileExtension) }) {
        return language
      }
    }
    guard let interpreter = interpreter(inFirstLine: firstLine) else { return nil }
    return all.first { $0.interpreters.contains(interpreter) }
  }

  /// The interpreter a `#!` line names, without its folder and version, such as `python` for
  /// `#!/usr/bin/env python3.12`.
  private static func interpreter(inFirstLine line: String) -> String? {
    guard line.hasPrefix("#!") else { return nil }
    let words = line.dropFirst(2).prefix(maximumShebangLength)
      .split(whereSeparator: { $0 == " " || $0 == "\t" || $0.isNewline })
    guard var program = words.first?.split(separator: "/").last else { return nil }
    if program == "env" {
      // `env` takes options and variable assignments before the program.
      guard
        let argument = words.dropFirst().first(where: { !$0.hasPrefix("-") && !$0.contains("=") })
      else { return nil }
      program = argument.split(separator: "/").last ?? argument
    }
    let name = program.prefix { !$0.isNumber && $0 != "." }
    return name.isEmpty ? nil : String(name)
  }
}
