import Foundation

/// A small, seedable generator so that random tests are reproducible.
struct SplitMix64: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

/// A three-way merge input built from a small vocabulary, so that equal
/// lines, overlapping edits and whitespace-only edits are frequent.
struct RandomMergeInput: CustomStringConvertible {
  let base: Data
  let a: Data
  let b: Data

  /// - Parameters:
  ///   - maximumLines: The largest number of base lines.
  ///   - maximumEdits: The largest number of edits per side.
  init(maximumLines: Int = 12, maximumEdits: Int = 3, using generator: inout SplitMix64) {
    let baseLines = (0..<Int.random(in: 0...maximumLines, using: &generator)).map { _ in
      "l\(Int.random(in: 0...5, using: &generator))"
    }
    base = Self.encode(baseLines, using: &generator)
    a = Self.encode(
      Self.edit(baseLines, maximumEdits: maximumEdits, using: &generator), using: &generator)
    b = Self.encode(
      Self.edit(baseLines, maximumEdits: maximumEdits, using: &generator), using: &generator)
  }

  var description: String {
    "base: \(base.text.debugDescription) a: \(a.text.debugDescription) b: \(b.text.debugDescription)"
  }

  /// Up to `maximumEdits` edits: delete, replace, indent or insert a line.
  private static func edit(
    _ lines: [String], maximumEdits: Int, using generator: inout SplitMix64
  ) -> [String] {
    var edited = lines
    for _ in 0..<Int.random(in: 0...maximumEdits, using: &generator) {
      let position = Int.random(in: 0...edited.count, using: &generator)
      let inRange = position < edited.count
      switch Int.random(in: 0...4, using: &generator) {
      case 0 where inRange:
        edited.remove(at: position)
      case 1 where inRange:
        edited[position] = "x\(Int.random(in: 0...3, using: &generator))"
      case 2 where inRange:
        edited[position] = edited[position].replacingOccurrences(of: "l", with: "l  ")
      default:
        edited.insert("n\(Int.random(in: 0...3, using: &generator))", at: position)
      }
    }
    return edited
  }

  /// Joins lines with LF, sometimes CRLF, and sometimes drops the last line
  /// ending.
  private static func encode(_ lines: [String], using generator: inout SplitMix64) -> Data {
    let lineEnding = Int.random(in: 0...5, using: &generator) == 0 ? "\r\n" : "\n"
    var text = lines.map { $0 + lineEnding }.joined()
    if !lines.isEmpty && Int.random(in: 0...5, using: &generator) == 0 {
      text.removeLast()
    }
    return Data(text)
  }
}
