extension RandomAccessCollection where Index == Int {
  /// The index of the first element for which `belongs` holds, in a collection where it holds
  /// for a suffix of the elements, or `endIndex` if it holds for none.
  func partitioningIndex(where belongs: (Element) -> Bool) -> Int {
    var low = startIndex
    var high = endIndex
    while low < high {
      let middle = low + (high - low) / 2
      if belongs(self[middle]) {
        high = middle
      } else {
        low = middle + 1
      }
    }
    return low
  }
}
