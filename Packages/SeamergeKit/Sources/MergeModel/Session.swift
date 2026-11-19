import Foundation
import TextBasics

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
  ///
  /// In a comparison with ignore rules, the lines whose text the rules match entirely may form
  /// unchanged blocks of their own with lines on one side only.
  public let blocks: [Block]

  /// The row grid of the panes.
  public let rowLayout: RowLayout

  /// The runs of lines that moved, in the order of their sources.
  ///
  /// In a comparison, the lines leave A and arrive in B, and each end is a changed block of its
  /// own with lines only in its input. Where moved lines also changed, the stretch that stayed
  /// equal under the comparison mode still moves, and the changed lines stay a removal and an
  /// addition. In a merge, a side removed lines of the base in one block and added them in
  /// another; both ends are whole blocks in the pane of that side, and a block counts only if the
  /// side's whole contribution to it moved unchanged. A run counts only if it is long enough and
  /// recurs exactly once. A more lenient comparison mode keeps the moves of a stricter one as long
  /// as the engine aligns the lines alike and each run still holds a line that occurs once on each
  /// side; uniqueness comes first.
  public let moves: [Move]

  /// The enabled ignore rules the comparison was asked to use, in their order; empty in a merge.
  ///
  /// The rules in ``ignoreRuleProblems`` took no effect; the others did.
  public let ignoreRules: [IgnoreRule]

  /// The rules of ``ignoreRules`` that took no effect, each with the reason.
  public let ignoreRuleProblems: [IgnoreRule: IgnoreRule.Problem]

  /// The files that take part, split into lines as the comparison split them.
  let files: [Role: ComparedFile]

  /// The position in ``moves`` of the move that ends in each block on the pane of each input.
  private let moveIndices: [MoveEnd: Int]

  /// A block on the pane of an input.
  private struct MoveEnd: Sendable, Hashable {
    var block: Int
    var role: Role
  }

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
      kind: .merge, options: options,
      files: comparedFiles(of: inputs, texts: texts, comparison: comparison),
      blocks: comparison.blocks)
  }

  /// Compares the older file `old` with the newer file `new`; they become A and B.
  ///
  /// Text that an enabled rule of `rules` matches does not count: lines that differ only there
  /// are equal. A rule whose pattern is invalid, or that takes longer than
  /// ``IgnoreRule/timeLimit`` for a file, takes no effect and is listed in
  /// ``ignoreRuleProblems``. The files are shown as they are. The comparison runs off the
  /// calling actor.
  ///
  /// - Throws: ``MergeModelError/binaryInput(_:)`` if a file is binary, or the error of the
  ///   comparison.
  @concurrent
  public static func diff(
    old: SourceFile, new: SourceFile, mode: ComparisonMode = .exact,
    ignoring rules: [IgnoreRule] = []
  ) async throws(MergeModelError) -> Session {
    let inputs = [Role.a: old, .b: new]
    let texts = try comparedTexts(of: inputs, in: mode)
    let enabledRules = rules.filter(\.isEnabled)
    var problems: [IgnoreRule: IgnoreRule.Problem] = [:]
    var validRules: [(rule: IgnoreRule, expression: NSRegularExpression)] = []
    for rule in enabledRules {
      switch rule.validated() {
      case .valid(let expression): validRules.append((rule, expression))
      case .invalid(let problem): problems[rule] = problem
      }
    }
    let files: [Role: ComparedFile]
    let comparison: EngineAdapter.Comparison
    if validRules.isEmpty {
      comparison = try EngineAdapter.diff(
        old: texts[.a, default: Data()], new: texts[.b, default: Data()], mode: mode)
      files = comparedFiles(of: inputs, texts: texts, comparison: comparison)
    } else {
      let masking = await IgnoreMask.masks(of: texts, rules: validRules, mode: mode)
      for rule in masking.slowRules { problems[rule] = .exceedsTimeLimit }
      comparison = try EngineAdapter.diff(
        old: masking.masks[.a]?.masked.utf8 ?? Data(),
        new: masking.masks[.b]?.masked.utf8 ?? Data(), mode: mode)
      files = inputs.reduce(into: [:]) { files, input in
        guard let mask = masking.masks[input.key] else { return }
        precondition(
          comparison.lineStarts[input.key] == mask.masked.lineStarts,
          "The engine splits the mask of \(input.key) into the lines of its file")
        files[input.key] = ComparedFile(file: input.value, mask: mask)
      }
    }
    return try Session(
      kind: .diff, options: ComparisonOptions(mode: mode), files: files,
      blocks: comparison.blocks, ignoreRules: enabledRules, ignoreRuleProblems: problems)
  }

  /// Compares the files of the session anew with `options`.
  ///
  /// A comparison of two files uses only the comparison mode, and the same ignore rules. The
  /// comparison runs off the calling actor.
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
      return try await Session.diff(old: a, new: b, mode: options.mode, ignoring: ignoreRules)
    }
  }

  /// Compares the files of a comparison of two files anew with `rules` and the same comparison
  /// mode.
  ///
  /// The comparison runs off the calling actor.
  ///
  /// - Precondition: The session is a comparison of two files; a merge takes no rules.
  /// - Throws: The error of the comparison.
  @concurrent
  public func recomputed(ignoring rules: [IgnoreRule]) async throws(MergeModelError) -> Session {
    guard kind == .diff, let a = file(for: .a), let b = file(for: .b) else {
      preconditionFailure("Only a comparison of two files takes ignore rules")
    }
    return try await Session.diff(old: a, new: b, mode: options.mode, ignoring: rules)
  }

  /// The files of `inputs` split as the engine split their `texts` in `comparison`.
  private static func comparedFiles(
    of inputs: [Role: SourceFile], texts: [Role: Data], comparison: EngineAdapter.Comparison
  ) -> [Role: ComparedFile] {
    inputs.reduce(into: [:]) { files, input in
      guard let text = texts[input.key], let lineStarts = comparison.lineStarts[input.key] else {
        return
      }
      files[input.key] = ComparedFile(file: input.value, text: text, lineStarts: lineStarts)
    }
  }

  private init(
    kind: Kind, options: ComparisonOptions, files: [Role: ComparedFile], blocks: [Block],
    ignoreRules: [IgnoreRule] = [], ignoreRuleProblems: [IgnoreRule: IgnoreRule.Problem] = [:]
  ) throws(MergeModelError) {
    self.kind = kind
    self.options = options
    self.files = files
    self.ignoreRules = ignoreRules
    self.ignoreRuleProblems = ignoreRuleProblems
    switch kind {
    case .diff:
      guard let old = files[.a], let new = files[.b] else {
        preconditionFailure("A comparison has the files A and B")
      }
      let separated = EntirelyMatchedLines.separating(
        blocks, of: old, with: new, mode: options.mode)
      let runs = try MoveDetection.runs(in: separated, files: files, mode: options.mode)
      let split = MoveDetection.splitting(separated, at: runs)
      self.blocks = split.blocks
      moves = split.moves
    case .merge:
      self.blocks = blocks
      moves = try MoveDetection.moves(inMerge: blocks, files: files, mode: options.mode)
    }
    rowLayout = RowLayout(blocks: self.blocks, files: files)
    var moveIndices: [MoveEnd: Int] = [:]
    for (index, move) in moves.enumerated() {
      for end in [move.source, move.destination] {
        moveIndices[MoveEnd(block: end.block, role: end.role)] = index
      }
    }
    self.moveIndices = moveIndices
  }

  /// The move that ends in `block` on the pane of `role`, or `nil` if none does.
  ///
  /// - Parameter origin: The side a comparison reads from, the one on the left. Read from B, as
  ///   after Swap Sides, the lines leave B and arrive in A. `nil` reads a comparison from A; a
  ///   merge reads its moves one way only.
  public func move(endingIn block: Block, on role: Role, readingFrom origin: Role? = nil) -> Move? {
    guard let index = moveIndices[MoveEnd(block: block.id, role: role)] else { return nil }
    return kind == .diff && origin == .b ? moves[index].reversed() : moves[index]
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
    // Mixed files count as one kind, whatever their mix.
    Set(files.values.compactMap { $0.file.lineEndingStyle.map(\.uniformLineEnding) }).count > 1
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
