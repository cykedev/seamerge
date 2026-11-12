import MergeModel
import Testing

/// Merges with a known sequence of blocks, for the tests of the result.
enum MergeFixture {
  /// The kinds of the blocks of ``nineBlocks()``.
  static let nineBlockKinds: [Block.Kind] = [
    .unchanged, .changedInA, .unchanged, .conflict, .unchanged, .changedInB, .unchanged,
    .conflict, .unchanged,
  ]

  /// The text of ``nineBlocks()`` after loading, one line of three characters per block, except
  /// for the preview of block 3, which has two.
  static let nineBlocksText = "u0\nA1\nu2\nA3\nB3\nu4\nB5\nu6\nY7\nu8\n"

  /// A merge of nine blocks, each with one line per input: unchanged, changed in A, unchanged, a
  /// conflict, unchanged, changed in B, unchanged, a conflict in which A deleted the line and B
  /// changed it, unchanged.
  static func nineBlocks() async throws -> Session {
    let session = try await merge(
      base: "u0\nx1\nu2\nx3\nu4\nx5\nu6\nx7\nu8\n",
      a: "u0\nA1\nu2\nA3\nu4\nx5\nu6\nu8\n",
      b: "u0\nx1\nu2\nB3\nu4\nB5\nu6\nY7\nu8\n")
    try #require(session.blocks.map(\.kind) == nineBlockKinds)
    return session
  }

  /// A merge of three blocks: unchanged, the same change in A and B, unchanged.
  static func sameChange() async throws -> Session {
    let session = try await merge(base: "u0\nx1\nu2\n", a: "u0\ny1\nu2\n", b: "u0\ny1\nu2\n")
    try #require(session.blocks.map(\.kind) == [.unchanged, .changedInBoth, .unchanged])
    return session
  }
}
