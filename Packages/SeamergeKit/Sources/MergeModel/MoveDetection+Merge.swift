extension MoveDetection {
  /// The moves of each side of a merge against the base, between whole blocks, in the order of
  /// their sources.
  ///
  /// A side moved lines where it removed lines of the base in one block, with nothing in their
  /// place, and added the same lines in another block, where the base has none. Both ends lie in
  /// the pane of that side. Blocks are never split, because decisions belong to them; a removal
  /// and an addition pair only when no other removal or addition of the side shares their
  /// fingerprint.
  ///
  /// - Throws: The error of the engine's comparison of a pair.
  static func moves(
    inMerge blocks: [Block], files: [Role: ComparedFile], mode: ComparisonMode
  ) throws(MergeModelError) -> [Move] {
    guard let base = files[.base] else { return [] }
    var moves: [Move] = []
    for side in [Role.a, .b] {
      guard let file = files[side] else { continue }
      var removals = UniqueBlocks()
      var additions = UniqueBlocks()
      for block in blocks where changers(of: block.kind).contains(side) {
        let lines = block.lines(in: side)
        if lines.isEmpty, !block.base.isEmpty {
          removals.add(block, fingerprint: fingerprint(of: block.base, in: base, mode: mode))
        } else if block.base.isEmpty, !lines.isEmpty {
          additions.add(block, fingerprint: fingerprint(of: lines, in: file, mode: mode))
        }
      }
      for (fingerprint, removal) in removals.blocks {
        guard removals.onlyBlock(with: fingerprint) == removal,
          let addition = additions.onlyBlock(with: fingerprint),
          try isMove(base, removal.base, file, addition.lines(in: side), mode: mode)
        else { continue }
        moves.append(
          Move(
            source: Move.End(block: removal.id, role: side, lines: removal.lines(in: side)),
            destination: Move.End(block: addition.id, role: side, lines: addition.lines(in: side))
          ))
      }
    }
    // The sort is stable, so a block both sides moved away from lists the move of A first.
    return moves.sorted { $0.source.block < $1.source.block }
  }

  /// Whether `lines` of `file` and `otherLines` of `otherFile` are a move: long enough, and equal
  /// under `mode` as the engine compares them.
  ///
  /// - Throws: The error of the engine's comparison.
  private static func isMove(
    _ file: ComparedFile, _ lines: Range<Int>, _ otherFile: ComparedFile,
    _ otherLines: Range<Int>, mode: ComparisonMode
  ) throws(MergeModelError) -> Bool {
    let text = file.compared.bytes(ofLines: lines)
    guard hasEnoughAlphanumerics(text) else { return false }
    let otherText = otherFile.compared.bytes(ofLines: otherLines)
    return try EngineAdapter.linesAreEqual(text, otherText, mode: mode)
  }

  /// The sides that changed a block of `kind` in a merge.
  private static func changers(of kind: Block.Kind) -> Set<Role> {
    switch kind {
    case .changedInA: [.a]
    case .changedInB: [.b]
    case .changedInBoth, .conflict: [.a, .b]
    case .unchanged, .changed: []
    }
  }

  /// A fingerprint of `lines` of `file` that runs of lines equal under `mode` share.
  private static func fingerprint(
    of lines: Range<Int>, in file: ComparedFile, mode: ComparisonMode
  ) -> UInt64 {
    lines.reduce(0xcbf2_9ce4_8422_2325) { hash, line in
      (hash ^ fingerprint(ofLine: line, in: file.compared, mode: mode)) &* 0x100_0000_01b3
    }
  }
}

/// Blocks of one kind of contribution of a side, such as its removals, by their fingerprints.
private struct UniqueBlocks {
  /// The blocks in order, each with its fingerprint.
  private(set) var blocks: [(fingerprint: UInt64, block: Block)] = []

  /// The last block added with each fingerprint.
  private var blocksByFingerprint: [UInt64: Block] = [:]

  /// The fingerprints that more than one block has.
  private var repeated: Set<UInt64> = []

  /// Adds `block` with its fingerprint.
  mutating func add(_ block: Block, fingerprint: UInt64) {
    blocks.append((fingerprint, block))
    if blocksByFingerprint.updateValue(block, forKey: fingerprint) != nil {
      repeated.insert(fingerprint)
    }
  }

  /// The only block with `fingerprint`, or `nil` if none or several have it.
  func onlyBlock(with fingerprint: UInt64) -> Block? {
    repeated.contains(fingerprint) ? nil : blocksByFingerprint[fingerprint]
  }
}
