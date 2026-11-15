import Foundation

/// Takes the lines whose text ignore rules match entirely out of the changes of a comparison of
/// two files.
///
/// The engine sees each such line as a placeholder, equal to every other one but to no real
/// line, so it reports an added or removed matched line as a change. Where such lines open or
/// close a changed block, they become unchanged blocks of their own: a line on each side pairs
/// up, and the lines one side has more stand alone, with no lines on the other side. Matched
/// lines between other changed lines stay part of the change. Neighboring unchanged blocks with
/// as many lines on each side are joined, so that only the lines that stand alone remain blocks
/// of their own.
enum EntirelyMatchedLines {
  /// The blocks of a comparison with the entirely matched lines at the edges of its changed
  /// blocks taken out, numbered anew by their position.
  ///
  /// Two matched lines pair up only if the engine would find them equal in `mode`: in
  /// ``ComparisonMode/exact``, only with the same line ending. Where a pair fails, the matched
  /// lines from there on stay part of the change.
  ///
  /// - Parameters:
  ///   - blocks: The blocks of the engine's comparison of `old` with `new`.
  ///   - mode: The comparison mode.
  static func separating(
    _ blocks: [Block], of old: ComparedFile, with new: ComparedFile, mode: ComparisonMode
  ) -> [Block] {
    let linesOfA = old.ruleMatches.entireLines
    let linesOfB = new.ruleMatches.entireLines
    guard !linesOfA.isEmpty || !linesOfB.isEmpty else { return blocks }
    func pair(_ lineInA: Int, _ lineInB: Int) -> Bool {
      mode != .exact
        || old.compared.bytes(ofLines: lineInA..<lineInA + 1)
          == new.compared.bytes(ofLines: lineInB..<lineInB + 1)
    }
    var separated: [Block] = []
    var a = 0
    var b = 0
    func append(_ kind: Block.Kind, a aCount: Int, b bCount: Int) {
      guard aCount > 0 || bCount > 0 else { return }
      let block = Block(id: 0, kind: kind, base: 0..<0, a: a..<a + aCount, b: b..<b + bCount)
      a += aCount
      b += bCount
      if let last = separated.last, last.kind == .unchanged, block.kind == .unchanged,
        last.a.count == last.b.count, aCount == bCount
      {
        separated[separated.count - 1] = Block(
          id: 0, kind: .unchanged, base: 0..<0, a: last.a.lowerBound..<a,
          b: last.b.lowerBound..<b)
      } else {
        separated.append(block)
      }
    }
    for block in blocks {
      guard block.kind == .changed else {
        append(block.kind, a: block.a.count, b: block.b.count)
        continue
      }
      let start = edge(
        prefixCount(of: block.a, in: linesOfA), prefixCount(of: block.b, in: linesOfB)
      ) { pair(block.a.lowerBound + $0, block.b.lowerBound + $0) }
      let restOfA = block.a.dropFirst(start.a)
      let restOfB = block.b.dropFirst(start.b)
      let end = edge(suffixCount(of: restOfA, in: linesOfA), suffixCount(of: restOfB, in: linesOfB))
      { pair(restOfA.upperBound - 1 - $0, restOfB.upperBound - 1 - $0) }
      append(.unchanged, a: start.paired, b: start.paired)
      append(.unchanged, a: start.a - start.paired, b: start.b - start.paired)
      append(.changed, a: restOfA.count - end.a, b: restOfB.count - end.b)
      append(.unchanged, a: end.a - end.paired, b: end.b - end.paired)
      append(.unchanged, a: end.paired, b: end.paired)
    }
    return separated.enumerated().map { index, block in
      Block(id: index, kind: block.kind, base: block.base, a: block.a, b: block.b)
    }
  }

  /// The matched lines that leave a change at one of its edges, where it has `countInA` and
  /// `countInB` matched lines in a row: as many pairs as `pairs` allows, counted from the edge,
  /// and then the lines that one side has more.
  ///
  /// If a pair fails before the shorter side runs out, only the pairs before it leave.
  private static func edge(
    _ countInA: Int, _ countInB: Int, pairs: (Int) -> Bool
  ) -> (paired: Int, a: Int, b: Int) {
    let shorter = min(countInA, countInB)
    let paired = (0..<shorter).prefix(while: pairs).count
    return paired < shorter ? (paired, paired, paired) : (paired, countInA, countInB)
  }

  /// The number of lines at the start of `lines` that `matched` holds.
  private static func prefixCount(of lines: Range<Int>, in matched: IndexSet) -> Int {
    lines.prefix { matched.contains($0) }.count
  }

  /// The number of lines at the end of `lines` that `matched` holds.
  private static func suffixCount(of lines: Range<Int>, in matched: IndexSet) -> Int {
    lines.reversed().prefix { matched.contains($0) }.count
  }
}
