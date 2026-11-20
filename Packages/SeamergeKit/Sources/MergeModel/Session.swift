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
  let files: Inputs<ComparedFile>

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
    let inputs = Inputs(base: base, a: a, b: b)
    let texts = try comparedTexts(of: inputs, in: options.mode)
    let comparison = try EngineAdapter.merge(texts, options: options)
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
    let inputs = Inputs(a: old, b: new)
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
    let files: Inputs<ComparedFile>
    let comparison: EngineAdapter.Comparison
    if validRules.isEmpty {
      comparison = try EngineAdapter.diff(old: texts.a, new: texts.b, mode: mode)
      files = comparedFiles(of: inputs, texts: texts, comparison: comparison)
    } else {
      let masking = await IgnoreMask.masks(of: texts, rules: validRules, mode: mode)
      for rule in masking.slowRules { problems[rule] = .exceedsTimeLimit }
      comparison = try EngineAdapter.diff(
        old: masking.masks.a.masked.utf8, new: masking.masks.b.masked.utf8, mode: mode)
      for (role, mask) in masking.masks {
        precondition(
          comparison.lineStarts[role] == mask.masked.lineStarts,
          "The engine splits the mask of \(role) into the lines of its file")
      }
      files = Inputs(
        a: ComparedFile(file: old, mask: masking.masks.a),
        b: ComparedFile(file: new, mask: masking.masks.b))
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
    switch kind {
    case .merge:
      return try await Session.merge(
        base: files.base?.file, a: files.a.file, b: files.b.file, options: options)
    case .diff:
      return try await Session.diff(
        old: files.a.file, new: files.b.file, mode: options.mode, ignoring: ignoreRules)
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
    precondition(kind == .diff, "Only a comparison of two files takes ignore rules")
    return try await Session.diff(
      old: files.a.file, new: files.b.file, mode: options.mode, ignoring: rules)
  }

  /// The files of `inputs` split as the engine split their `texts` in `comparison`.
  private static func comparedFiles(
    of inputs: Inputs<SourceFile>, texts: Inputs<Data>, comparison: EngineAdapter.Comparison
  ) -> Inputs<ComparedFile> {
    var base: ComparedFile?
    if let file = inputs.base, let text = texts.base, let lineStarts = comparison.lineStarts.base {
      base = ComparedFile(file: file, text: text, lineStarts: lineStarts)
    }
    return Inputs(
      base: base,
      a: ComparedFile(file: inputs.a, text: texts.a, lineStarts: comparison.lineStarts.a),
      b: ComparedFile(file: inputs.b, text: texts.b, lineStarts: comparison.lineStarts.b))
  }

  private init(
    kind: Kind, options: ComparisonOptions, files: Inputs<ComparedFile>, blocks: [Block],
    ignoreRules: [IgnoreRule] = [], ignoreRuleProblems: [IgnoreRule: IgnoreRule.Problem] = [:]
  ) throws(MergeModelError) {
    self.kind = kind
    self.options = options
    self.files = files
    self.ignoreRules = ignoreRules
    self.ignoreRuleProblems = ignoreRuleProblems
    switch kind {
    case .diff:
      let separated = EntirelyMatchedLines.separating(
        blocks, of: files.a, with: files.b, mode: options.mode)
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

  /// The files of the inputs.
  ///
  /// The inputs are made anew on each access; code that reads them repeatedly takes them into a
  /// constant first.
  public var inputs: Inputs<SourceFile> { files.mapValues(\.file) }

  /// The inputs that take part, in the order base, A, B.
  public var roles: [Role] { files.roles }

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
    of inputs: Inputs<SourceFile>, in mode: ComparisonMode
  ) throws(MergeModelError) -> Inputs<Data> {
    try inputs.mapValuesWithRoles { role, file throws(MergeModelError) in
      guard let text = file.comparedText(in: mode) else { throw .binaryInput(role) }
      return text
    }
  }
}
