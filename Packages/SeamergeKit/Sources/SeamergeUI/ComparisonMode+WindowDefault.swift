import MergeModel

extension ComparisonMode {
  /// The mode a session window compares in unless the user chooses another: whitespace changes
  /// are ignored, since a reindented line rarely matters when merging.
  ///
  /// The merge model starts in ``exact`` as the neutral choice of a library; this is the choice
  /// of the app, and the subtitle names a mode only when it differs from it.
  static let windowDefault = ComparisonMode.ignoreWhitespaceAmount
}
