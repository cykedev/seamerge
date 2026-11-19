extension Range where Bound == Int {
  /// The last index for which `holds` is true, in a range where it is true for a prefix of the
  /// indices; the first index counts whatever `holds` says of it, and an empty range answers its
  /// lower bound.
  ///
  /// This finds the line, row or block that a position falls in from where each one starts, with
  /// a position before the first belonging to the first.
  @inlinable
  package func lastIndex(holding holds: (Int) -> Bool) -> Int {
    guard count > 1 else { return lowerBound }
    return (lowerBound + 1..<upperBound).partitioningIndex { !holds($0) } - 1
  }
}
