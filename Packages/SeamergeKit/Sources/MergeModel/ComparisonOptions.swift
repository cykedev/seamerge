/// How a session compares its inputs.
public struct ComparisonOptions: Sendable, Hashable {
  /// How lines are compared.
  public var mode: ComparisonMode

  /// How a merge resolves overlapping changes; a comparison of two files does not use it, and a
  /// merge without a base always merges as if the base were empty.
  public var strategy: MergeStrategy

  /// Creates options for a session.
  public init(mode: ComparisonMode = .exact, strategy: MergeStrategy = .optimal) {
    self.mode = mode
    self.strategy = strategy
  }
}

/// Which differences between lines count.
///
/// Every mode other than ``exact`` also ends a line at a lone carriage return, so the lines of a
/// file depend on the mode.
public enum ComparisonMode: Sendable, Hashable, CaseIterable {
  /// Lines are equal only if their bytes are identical, including the line ending.
  case exact

  /// LF, CRLF and CR line endings are equal.
  case ignoreLineEndings

  /// Runs of spaces and tabs are equal regardless of length and trailing whitespace is ignored,
  /// but whitespace where there was none is a change. Line endings are ignored.
  case ignoreWhitespaceAmount

  /// Spaces and tabs are ignored entirely. Line endings are ignored.
  case ignoreAllWhitespace
}

/// How a merge resolves overlapping changes, after the merge grids of the Perforce engine.
public enum MergeStrategy: Sendable, Hashable, CaseIterable {
  /// The default of the Perforce engine.
  case optimal

  /// Reports a conflict where ``optimal`` accepts changes that touch the same region, such as an
  /// identical change next to a different one.
  case guarded

  /// Like ``optimal``, but resolves some ambiguous insertions the way `diff3` does.
  case diff3

  /// ``guarded`` and ``diff3`` combined.
  case guardedDiff3
}
