import Foundation
import MergeEngine
import MergeModel

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

/// The inputs of a merge built from a small vocabulary, so that equal lines, overlapping edits,
/// whitespace-only edits, CRLF line endings and missing final line endings are frequent.
struct RandomMergeInput: CustomStringConvertible {
  let base: String?
  let a: String
  let b: String

  init(using generator: inout SplitMix64) {
    let baseLines = (0..<Int.random(in: 0...8, using: &generator)).map { _ in
      ["l0", "l1", "l2", "ä3", "l4"].randomElement(using: &generator) ?? ""
    }
    let hasBase = Int.random(in: 0..<6, using: &generator) > 0
    base = hasBase ? Self.text(of: baseLines, using: &generator) : nil
    a = Self.text(of: Self.edit(baseLines, using: &generator), using: &generator)
    b = Self.text(of: Self.edit(baseLines, using: &generator), using: &generator)
  }

  /// The inputs `base`, `a` and `b`.
  init(base: String?, a: String, b: String) {
    self.base = base
    self.a = a
    self.b = b
  }

  var description: String {
    "base: \(base.debugDescription) a: \(a.debugDescription) b: \(b.debugDescription)"
  }

  /// The session of the inputs.
  func session(
    mode: ComparisonMode, strategy: MergeModel.MergeStrategy
  ) async throws -> Session {
    try await Session.merge(
      base: base.map { SourceFile($0, label: "base") }, a: SourceFile(a, label: "a"),
      b: SourceFile(b, label: "b"), options: ComparisonOptions(mode: mode, strategy: strategy))
  }

  /// The engine's merge of the inputs, as a session runs it.
  func engineMerge(mode: ComparisonMode, strategy: MergeModel.MergeStrategy) throws -> Merge {
    let engineStrategy: MergeEngine.MergeStrategy =
      switch strategy {
      case _ where base == nil: .twoWay
      case .optimal: .optimal
      case .guarded: .guarded
      case .diff3: .diff3
      case .guardedDiff3: .guardedDiff3
      }
    return try Merge(
      base: Data((base ?? "").utf8), a: Data(a.utf8), b: Data(b.utf8), whitespace: Whitespace(mode),
      strategy: engineStrategy)
  }

  /// Up to three edits: delete, replace, indent or insert a line.
  private static func edit(_ lines: [String], using generator: inout SplitMix64) -> [String] {
    var edited = lines
    for _ in 0..<Int.random(in: 0...3, using: &generator) {
      let position = Int.random(in: 0...edited.count, using: &generator)
      let inRange = position < edited.count
      switch Int.random(in: 0...4, using: &generator) {
      case 0 where inRange:
        edited.remove(at: position)
      case 1 where inRange:
        edited[position] = "x\(Int.random(in: 0...2, using: &generator))"
      case 2 where inRange:
        edited[position] = " " + edited[position] + "\t"
      default:
        edited.insert("n\(Int.random(in: 0...2, using: &generator))", at: position)
      }
    }
    return edited
  }

  /// The lines joined with LF or, now and then, CRLF, and without a final line ending now and
  /// then.
  private static func text(of lines: [String], using generator: inout SplitMix64) -> String {
    let lineEnding = Int.random(in: 0..<5, using: &generator) == 0 ? "\r\n" : "\n"
    var text = lines.map { $0 + lineEnding }.joined()
    if Int.random(in: 0..<3, using: &generator) == 0 {
      text = String(text.dropLast())
    }
    return text
  }
}

extension Whitespace {
  /// The engine's mode for `mode`, as a session uses it.
  init(_ mode: ComparisonMode) {
    self =
      switch mode {
      case .exact: .exact
      case .ignoreLineEndings: .ignoreLineEndings
      case .ignoreWhitespaceAmount: .ignoreAmount
      case .ignoreAllWhitespace: .ignoreAll
      }
  }
}
