import Foundation

/// Finds the lines that moved: removed at one place and added at another, unchanged under the
/// comparison mode.
///
/// The lines are read as the engine compared them, without the text that ignore rules match.
///
/// Candidates come from fingerprints of the lines, which follow the comparison mode: lines that
/// the mode counts as equal share a fingerprint. A candidate grows from an anchor, a line whose
/// fingerprint occurs once among the removed and once among the added lines, as far as the lines
/// next to it match on both sides. The engine then compares the two runs, and only lines it finds
/// equal under the mode become a move: the stretch around an anchor that stayed equal, also where
/// the lines next to it changed. A move needs an anchor: without one, its lines may recur more
/// than once or match more than one other run, and are left alone, since a missed move is better
/// than a wrong one. Each line is looked at a fixed number of times, so the search takes time in
/// proportion to the size of the files, and so does the engine's comparison of the candidates.
enum MoveDetection {
  /// The number of letters and digits a run needs to count as a move, as with
  /// `git diff --color-moved`: braces, blank lines and a lone `return` never move.
  static let minimumAlphanumericCount = 20

  /// A run of lines removed from A within one changed block and the run of lines added to B in
  /// another place that it recurs as.
  struct Run: Hashable {
    /// The index of the block that holds the removed lines.
    var blockInA: Int

    /// The removed lines of A.
    var a: Range<Int>

    /// The index of the block that holds the added lines.
    var blockInB: Int

    /// The added lines of B.
    var b: Range<Int>
  }

  /// The runs that moved between the changed blocks of a comparison of A with B, ordered by the
  /// removed lines.
  ///
  /// - Throws: The error of the engine's comparison of a run.
  static func runs(
    in blocks: [Block], files: [Role: ComparedFile], mode: ComparisonMode
  ) throws(MergeModelError) -> [Run] {
    guard let old = files[.a], let new = files[.b] else { return [] }
    let removed = ChangedLines(of: .a, in: blocks, file: old, mode: mode)
    let added = ChangedLines(of: .b, in: blocks, file: new, mode: mode)
    var isUsedInA = [Bool](repeating: false, count: old.lineCount)
    var isUsedInB = [Bool](repeating: false, count: new.lineCount)

    func match(_ lineInA: Int, _ lineInB: Int, blocks anchor: (a: Int, b: Int)) -> Bool {
      removed.block(ofLine: lineInA) == anchor.a && added.block(ofLine: lineInB) == anchor.b
        && !isUsedInA[lineInA] && !isUsedInB[lineInB]
        && removed.fingerprint(ofLine: lineInA) == added.fingerprint(ofLine: lineInB)
    }

    var runs: [Run] = []
    for line in removed.lines {
      let fingerprint = removed.fingerprint(ofLine: line)
      guard !isUsedInA[line], removed.onlyLine(with: fingerprint) == line,
        let partner = added.onlyLine(with: fingerprint), !isUsedInB[partner],
        let blockInA = removed.block(ofLine: line), let blockInB = added.block(ofLine: partner)
      else { continue }
      let anchor = (a: blockInA, b: blockInB)
      var start = (a: line, b: partner)
      while match(start.a - 1, start.b - 1, blocks: anchor) { start = (start.a - 1, start.b - 1) }
      var end = (a: line + 1, b: partner + 1)
      while match(end.a, end.b, blocks: anchor) { end = (end.a + 1, end.b + 1) }
      // The lines are spent whether or not the run turns out to be a move, so that no later
      // anchor on the same run compares it again.
      for lineInA in start.a..<end.a { isUsedInA[lineInA] = true }
      for lineInB in start.b..<end.b { isUsedInB[lineInB] = true }
      let shared = try EngineAdapter.equalLines(
        old.compared.bytes(ofLines: start.a..<end.a), new.compared.bytes(ofLines: start.b..<end.b),
        mode: mode)
      for stretch in shared {
        let a = start.a + stretch.first.lowerBound..<start.a + stretch.first.upperBound
        let b = start.b + stretch.second.lowerBound..<start.b + stretch.second.upperBound
        // The engine pairs an anchor with a line it finds equal, which shares the anchor's
        // fingerprint and is therefore the only added line that has it.
        let holdsAnchor = a.contains { lineInA in
          let fingerprint = removed.fingerprint(ofLine: lineInA)
          return removed.onlyLine(with: fingerprint) == lineInA
            && added.onlyLine(with: fingerprint) != nil
        }
        guard holdsAnchor, hasEnoughAlphanumerics(old.compared.bytes(ofLines: a))
        else { continue }
        runs.append(Run(blockInA: blockInA, a: a, blockInB: blockInB, b: b))
      }
    }
    return runs
  }

  /// The blocks of a comparison with each of `runs` in a block of its own, and the moves between
  /// those blocks.
  ///
  /// A changed block that holds runs is cut at their bounds. The lines between the runs stay
  /// changed and pair up in order: the lines of A before its first run with the lines of B before
  /// its first run, and so on. Where one side has no runs left, its lines pair line by line with
  /// those of the other side between its runs, and the last change takes the rest. Every block is
  /// numbered anew by its position, and the blocks still cover both files without a gap.
  ///
  /// - Precondition: `runs` are the runs of `blocks`, ordered by their lines in A.
  static func splitting(_ blocks: [Block], at runs: [Run]) -> (blocks: [Block], moves: [Move]) {
    let runsInA = Dictionary(grouping: runs, by: \.blockInA)
    let runsInB = Dictionary(grouping: runs, by: \.blockInB).mapValues { runs in
      runs.sorted { $0.b.lowerBound < $1.b.lowerBound }
    }
    var split: [Block] = []
    var sources: [Run: Int] = [:]
    var destinations: [Run: Int] = [:]
    func append(kind: Block.Kind = .changed, base: Range<Int> = 0..<0, a: Range<Int>, b: Range<Int>)
    {
      split.append(Block(id: split.count, kind: kind, base: base, a: a, b: b))
    }
    for (index, block) in blocks.enumerated() {
      let inA = runsInA[index] ?? []
      let inB = runsInB[index] ?? []
      guard !inA.isEmpty || !inB.isEmpty else {
        append(kind: block.kind, base: block.base, a: block.a, b: block.b)
        continue
      }
      var a = block.a.lowerBound
      var b = block.b.lowerBound
      for position in 0...max(inA.count, inB.count) {
        var endOfA = position < inA.count ? inA[position].a.lowerBound : block.a.upperBound
        var endOfB = position < inB.count ? inB[position].b.lowerBound : block.b.upperBound
        // A side without runs left keeps lines for the changes after the other side's next run.
        if position < inA.count, position >= inB.count { endOfB = min(endOfB, b + endOfA - a) }
        if position < inB.count, position >= inA.count { endOfA = min(endOfA, a + endOfB - b) }
        if a < endOfA || b < endOfB {
          append(a: a..<endOfA, b: b..<endOfB)
          a = endOfA
          b = endOfB
        }
        if position < inA.count {
          sources[inA[position]] = split.count
          append(a: inA[position].a, b: b..<b)
          a = inA[position].a.upperBound
        }
        if position < inB.count {
          destinations[inB[position]] = split.count
          append(a: a..<a, b: inB[position].b)
          b = inB[position].b.upperBound
        }
      }
    }
    let moves = runs.map { run in
      guard let source = sources[run], let destination = destinations[run] else {
        preconditionFailure("A run lies in the blocks it names")
      }
      return Move(
        source: Move.End(block: source, role: .a, lines: run.a),
        destination: Move.End(block: destination, role: .b, lines: run.b))
    }
    return (split, moves)
  }

  /// Whether `text` has at least ``minimumAlphanumericCount`` letters and digits.
  static func hasEnoughAlphanumerics(_ text: Data) -> Bool {
    var count = 0
    for scalar in String(decoding: text, as: UTF8.self).unicodeScalars
    where scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
      count += 1
      if count == minimumAlphanumericCount { return true }
    }
    return false
  }

  /// A fingerprint of a line that the lines equal to it under `mode` share, as the engine
  /// hashes lines: its bytes with the line ending in ``ComparisonMode/exact``, without it in the
  /// other modes; with each run of spaces and tabs as one space and none at the end in
  /// ``ComparisonMode/ignoreWhitespaceAmount``; without spaces and tabs in
  /// ``ComparisonMode/ignoreAllWhitespace``.
  ///
  /// The engine still has the last word on whether two lines are equal.
  static func fingerprint(ofLine line: Int, in text: LineText, mode: ComparisonMode) -> UInt64 {
    let range =
      mode == .exact
      ? text.byteRange(ofLines: line..<line + 1) : text.contentByteRange(ofLine: line)
    // 64-bit FNV-1a: fast, and the same in every process, unlike `Hasher`.
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    func add(_ byte: UInt8) { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
    var followsWhitespace = false
    text.utf8.withUnsafeBytes { bytes in
      for byte in bytes[range] {
        if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") {
          switch mode {
          case .exact, .ignoreLineEndings: add(byte)
          case .ignoreWhitespaceAmount: followsWhitespace = true
          case .ignoreAllWhitespace: break
          }
          continue
        }
        if followsWhitespace {
          add(UInt8(ascii: " "))
          followsWhitespace = false
        }
        add(byte)
      }
    }
    return hash
  }
}

/// The lines of one input that lie in the changed blocks of a comparison, with their
/// fingerprints.
private struct ChangedLines {
  /// The changed lines in order.
  private(set) var lines: [Int] = []

  /// The index of the changed block that holds each line of the file, or `nil` for a line of an
  /// unchanged block.
  private var blocks: [Int?]

  /// The fingerprint of each line of the file; 0 for a line of an unchanged block.
  private var fingerprints: [UInt64]

  /// The changed line that has each fingerprint, for fingerprints that only one changed line has.
  private var onlyLines: [UInt64: Int] = [:]

  /// Collects the lines of `role` in the changed blocks of `blocks`.
  init(of role: Role, in blocks: [Block], file: ComparedFile, mode: ComparisonMode) {
    self.blocks = [Int?](repeating: nil, count: file.lineCount)
    fingerprints = [UInt64](repeating: 0, count: file.lineCount)
    var repeated: Set<UInt64> = []
    for (index, block) in blocks.enumerated() where block.kind == .changed {
      for line in block.lines(in: role) {
        let fingerprint = MoveDetection.fingerprint(ofLine: line, in: file.compared, mode: mode)
        lines.append(line)
        self.blocks[line] = index
        fingerprints[line] = fingerprint
        if onlyLines.updateValue(line, forKey: fingerprint) != nil {
          repeated.insert(fingerprint)
        }
      }
    }
    for fingerprint in repeated {
      onlyLines[fingerprint] = nil
    }
  }

  /// The index of the changed block that holds `line`, or `nil` if it is not a changed line or
  /// lies outside the file.
  func block(ofLine line: Int) -> Int? {
    blocks.indices.contains(line) ? blocks[line] : nil
  }

  /// The fingerprint of a changed line.
  func fingerprint(ofLine line: Int) -> UInt64 {
    fingerprints[line]
  }

  /// The only changed line with `fingerprint`, or `nil` if none or several have it.
  func onlyLine(with fingerprint: UInt64) -> Int? {
    onlyLines[fingerprint]
  }
}
