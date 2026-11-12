/// Where the changed blocks of a window lie from the current block on: the blocks that the
/// commands of the Go menu jump to.
///
/// Every jump stops at the last block it can reach: past the last conflict or change, there is
/// no next one.
struct BlockNavigation: Equatable {
  /// Whether each changed block is a conflict that is still open, in the order of the blocks.
  let isOpenConflict: [Bool]

  /// The index of the current block, if there is one.
  let current: Int?

  /// The first open conflict after the current block, or the first one if no block is current.
  var nextOpenConflict: Int? {
    isOpenConflict.indices.first { $0 > (current ?? -1) && isOpenConflict[$0] }
  }

  /// The last open conflict before the current block, or `nil` if no block is current.
  var previousOpenConflict: Int? {
    guard let current else { return nil }
    return isOpenConflict.indices.last { $0 < current && isOpenConflict[$0] }
  }

  /// The change after the current block, or the first one if no block is current.
  var nextChange: Int? {
    let next = (current ?? -1) + 1
    return isOpenConflict.indices.contains(next) ? next : nil
  }

  /// The change before the current block, or `nil` if no block is current.
  var previousChange: Int? {
    guard let current, current > 0 else { return nil }
    return current - 1
  }

  /// The first change, unless it is current.
  var firstChange: Int? {
    isOpenConflict.isEmpty || current == 0 ? nil : 0
  }

  /// The last change, unless it is current.
  var lastChange: Int? {
    let last = isOpenConflict.count - 1
    return last < 0 || current == last ? nil : last
  }

  /// The first open conflict of all, wherever the current block is.
  var firstOpenConflict: Int? {
    isOpenConflict.firstIndex(of: true)
  }

  /// How many conflicts are still open.
  var openConflictCount: Int {
    isOpenConflict.count { $0 }
  }
}
