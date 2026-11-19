extension RandomAccessCollection {
  /// The index of the first element for which `belongs` holds, in a collection where it holds for
  /// a suffix of the elements, or `endIndex` if it holds for none.
  ///
  /// The search takes a logarithmic number of steps. It is inlinable so that callers in other
  /// modules get a version specialized for their collection and predicate.
  @inlinable
  package func partitioningIndex(where belongs: (Element) -> Bool) -> Index {
    var low = startIndex
    var remaining = count
    while remaining > 0 {
      let half = remaining / 2
      let middle = index(low, offsetBy: half)
      if belongs(self[middle]) {
        remaining = half
      } else {
        low = index(after: middle)
        remaining -= half + 1
      }
    }
    return low
  }
}
