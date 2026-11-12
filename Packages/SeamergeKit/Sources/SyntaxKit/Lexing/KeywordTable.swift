/// The keywords of a language, looked up by the bytes of a word without building a string.
struct KeywordTable: Sendable {
  /// The keywords as bytes, grouped by their first byte.
  private let keywordsByFirstByte: [[[UInt8]]]
  private let ignoresCase: Bool

  init(_ keywords: [String], ignoresCase: Bool) {
    var keywordsByFirstByte = [[[UInt8]]](repeating: [], count: 256)
    for keyword in keywords {
      let bytes = Array((ignoresCase ? keyword.lowercased() : keyword).utf8)
      precondition(!bytes.isEmpty, "A keyword must not be empty")
      keywordsByFirstByte[Int(bytes[0])].append(bytes)
    }
    self.keywordsByFirstByte = keywordsByFirstByte
    self.ignoresCase = ignoresCase
  }

  /// Whether the word in a range of a line is a keyword.
  func contains(_ word: Range<Int>, in line: LineBytes) -> Bool {
    let first = ignoresCase ? line[word.lowerBound].lowercasedASCII : line[word.lowerBound]
    for keyword in keywordsByFirstByte[Int(first)] where keyword.count == word.count {
      let matches =
        ignoresCase
        ? line.hasPrefix(lowercased: keyword, at: word.lowerBound)
        : line.hasPrefix(keyword, at: word.lowerBound)
      if matches { return true }
    }
    return false
  }
}
