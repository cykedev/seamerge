import Foundation

/// An open merge or comparison: its files, the blocks the engine found and the row grid that
/// aligns them.
///
/// A session is created in the background, because comparing large files takes a moment, and
/// does not change afterwards. Another comparison mode makes a new session from the same files.
public struct Session: Sendable {
  /// Whether a session merges or compares.
  public enum Kind: Sendable, Hashable {
    /// A merge of A and B, with or without their base.
    case merge

    /// A comparison of an older file, A, with a newer one, B.
    case diff
  }

  /// Whether the session merges or compares.
  public let kind: Kind

  /// How the files were compared.
  public let options: ComparisonOptions

  /// The blocks in input order; their ``Block/id`` is their position.
  public let blocks: [Block]

  /// The row grid of the panes.
  public let rowLayout: RowLayout

  /// The runs of lines that moved, in the order of their sources.
  ///
  /// In a comparison, the lines leave A and arrive in B. Where moved lines also changed, the
  /// stretch that stayed equal under the comparison mode still moves, and the changed lines stay
  /// a removal and an addition. A run counts only if it is long enough and recurs exactly once. A
  /// more lenient comparison mode keeps the moves of a stricter one as long as the engine aligns
  /// the lines alike and each run still holds a line that occurs once on each side; uniqueness
  /// comes first.
  public let moves: [Move]

  /// The files that take part, split into lines as the comparison split them.
  let files: [Role: ComparedFile]

  /// Merges the changes from `base` to `a` and from `base` to `b`, or merges `a` and `b` as if
  /// their base were empty when there is none.
  ///
  /// A is the incoming side and B the own side. The comparison runs off the calling actor.
  ///
  /// - Throws: ``MergeModelError/binaryInput(_:)`` if a file is binary, or the error of the
  ///   comparison.
  @concurrent
  public static func merge(
    base: SourceFile?, a: SourceFile, b: SourceFile, options: ComparisonOptions = .init()
  ) async throws(MergeModelError) -> Session {
    let inputs = [Role.base: base, .a: a, .b: b].compactMapValues(\.self)
    let texts = try comparedTexts(of: inputs, in: options.mode)
    let comparison = try EngineAdapter.merge(
      base: texts[.base], a: texts[.a, default: Data()], b: texts[.b, default: Data()],
      options: options)
    return try Session(
      kind: .merge, options: options, inputs: inputs, texts: texts, comparison: comparison)
  }

  /// Compares the older file `old` with the newer file `new`; they become A and B.
  ///
  /// The comparison runs off the calling actor.
  ///
  /// - Throws: ``MergeModelError/binaryInput(_:)`` if a file is binary, or the error of the
  ///   comparison.
  @concurrent
  public static func diff(
    old: SourceFile, new: SourceFile, mode: ComparisonMode = .exact
  ) async throws(MergeModelError) -> Session {
    let inputs = [Role.a: old, .b: new]
    let texts = try comparedTexts(of: inputs, in: mode)
    let comparison = try EngineAdapter.diff(
      old: texts[.a, default: Data()], new: texts[.b, default: Data()], mode: mode)
    return try Session(
      kind: .diff, options: ComparisonOptions(mode: mode), inputs: inputs, texts: texts,
      comparison: comparison)
  }

  /// Compares the files of the session anew with `options`.
  ///
  /// A comparison of two files uses only the comparison mode. The comparison runs off the calling
  /// actor.
  ///
  /// - Throws: The error of the comparison.
  @concurrent
  public func recomputed(options: ComparisonOptions) async throws(MergeModelError) -> Session {
    guard let a = file(for: .a), let b = file(for: .b) else {
      preconditionFailure("Every session has the inputs A and B")
    }
    switch kind {
    case .merge:
      return try await Session.merge(base: file(for: .base), a: a, b: b, options: options)
    case .diff:
      return try await Session.diff(old: a, new: b, mode: options.mode)
    }
  }

  private init(
    kind: Kind, options: ComparisonOptions, inputs: [Role: SourceFile], texts: [Role: Data],
    comparison: EngineAdapter.Comparison
  ) throws(MergeModelError) {
    let files = Dictionary(
      uniqueKeysWithValues: inputs.compactMap { role, file -> (Role, ComparedFile)? in
        guard let text = texts[role], let lineStarts = comparison.lineStarts[role] else {
          return nil
        }
        return (role, ComparedFile(file: file, text: text, lineStarts: lineStarts))
      })
    self.kind = kind
    self.options = options
    self.files = files
    blocks = comparison.blocks
    rowLayout = RowLayout(blocks: comparison.blocks, files: files)
    moves =
      switch kind {
      case .diff:
        try MoveDetection.runs(in: comparison.blocks, files: files, mode: options.mode).map { run in
          Move(
            source: Move.End(block: run.blockInA, role: .a, lines: run.a),
            destination: Move.End(block: run.blockInB, role: .b, lines: run.b))
        }
      case .merge: []
      }
  }

  /// The inputs that take part, in the order base, A, B.
  public var roles: [Role] { Role.allCases.filter { files[$0] != nil } }

  /// The file of `role`, or `nil` if the input does not take part.
  public func file(for role: Role) -> SourceFile? {
    files[role]?.file
  }

  /// Whether the files that have line breaks end their lines differently.
  ///
  /// A file with mixed line endings differs from one with uniform line endings, but not from
  /// another file with mixed line endings. The comparison may treat the line endings as equal,
  /// so the header shows the difference instead.
  public var lineEndingsDiffer: Bool {
    Set(files.values.compactMap(\.file.lineEndings)).count > 1
  }

  /// The text of each file as the comparison sees it.
  ///
  /// - Throws: ``MergeModelError/binaryInput(_:)`` for the first binary file.
  private static func comparedTexts(
    of inputs: [Role: SourceFile], in mode: ComparisonMode
  ) throws(MergeModelError) -> [Role: Data] {
    var texts: [Role: Data] = [:]
    for role in Role.allCases {
      guard let file = inputs[role] else { continue }
      guard let text = file.comparedText(in: mode) else { throw .binaryInput(role) }
      texts[role] = text
    }
    return texts
  }
}
