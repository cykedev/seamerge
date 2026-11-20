import MergeModel

extension [IgnoreRule] {
  /// Whether these switched-on rules leave out the same text as `others`: whether they have the
  /// same patterns in the same order, whatever their names.
  func hasTheSameEffect(as others: [IgnoreRule]) -> Bool {
    map(\.pattern) == others.map(\.pattern)
  }
}
