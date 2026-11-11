/// How lines are compared, mirroring the Perforce `-d` flags.
///
/// All modes other than ``exact`` also treat a lone carriage return as the end
/// of a line, so line numbers depend on the mode.
public enum Whitespace: Sendable, Hashable, CaseIterable {
  /// Lines are equal only if their bytes are identical, including the line
  /// ending.
  case exact

  /// LF, CRLF and CR line endings are equal (`-dl`).
  ///
  /// A last line without a line ending equals the same line ending in LF or
  /// CR, but not one ending in CRLF.
  case ignoreLineEndings

  /// Runs of spaces and tabs are equal regardless of length, and trailing
  /// whitespace is ignored; whitespace that appears where there was none is a
  /// change (`-db`). Line endings are ignored.
  case ignoreAmount

  /// Spaces and tabs are ignored entirely (`-dw`). Line endings are ignored.
  case ignoreAll
}

/// How the three-way merge resolves overlapping changes, mirroring the
/// Perforce merge grid flags.
public enum MergeStrategy: Sendable, Hashable, CaseIterable {
  /// The Perforce default.
  case optimal

  /// Reports a conflict where the default would accept changes that touch the
  /// same region, such as an identical change next to a different one (`-dg`).
  case guarded

  /// Like ``optimal``, but resolves some ambiguous insertions the way `diff3`
  /// does (`-dx`).
  case diff3

  /// ``guarded`` and ``diff3`` combined (`-dgx`).
  case guardedDiff3

  /// Ignores the base and merges as if it were empty (`-dt`).
  case twoWay
}

/// How ``TokenDiff`` splits text into tokens.
public enum TokenGranularity: Sendable, Hashable {
  /// Runs of one character class: letters, digits and non-ASCII bytes;
  /// whitespace; punctuation; line endings (Perforce `WClassReader`).
  case characterClasses

  /// Words, each including the single whitespace byte that ends it
  /// (Perforce `WordReader`).
  case words
}

/// An error reported by the engine.
public enum EngineError: Error, Sendable, Hashable {
  /// An input is larger than `Int32.max` bytes, the limit of the engine's
  /// index types.
  case inputTooLarge

  /// Memory could not be allocated.
  case outOfMemory

  /// The engine failed unexpectedly. This indicates a bug in the engine or
  /// in this package.
  case internalFailure
}
