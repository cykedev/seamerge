/// The switch of a result to a new comparison of the same files, in another comparison mode or
/// with another merge strategy.
public struct ModeSwitch: Sendable {
  /// The plan that replaces the result text and the document with those of the new comparison.
  ///
  /// After applying it, ``ResultDocument/session`` is the new session. It is a single undo step;
  /// undoing it brings back the old session.
  public let plan: EditPlan

  /// The number of decisions that have no block with the same lines in the new comparison and
  /// are discarded.
  public let discardedDecisionCount: Int
}

extension ResultDocument {
  /// The switch to `session`, a new comparison of the same files, keeping each decision whose
  /// block has the same lines in every input there.
  ///
  /// A kept decision keeps its sources, or its text if it was edited by hand; if its sources are
  /// those the new block is loaded with, the block is untouched or automatic. Every other block
  /// starts as after loading.
  ///
  /// - Parameters:
  ///   - session: A merge of the files of this document's session.
  ///   - text: The result text, as long as the segments together.
  public func planSwitching(to session: Session, text: String) -> ModeSwitch {
    let fresh = ResultDocument(session: session)
    var decisionsByLines: [[Range<Int>]: Int] = [:]
    for index in segments.indices where !segments[index].hasSameDecision(as: initialSegments[index])
    {
      decisionsByLines[self.session.byteRanges(of: self.session.blocks[index])] = index
    }

    var segments = fresh.segments
    var editedTexts: [Int: String] = [:]
    var keptCount = 0
    let oldTexts = split(text)
    for block in session.blocks {
      guard let index = decisionsByLines[session.byteRanges(of: block)] else { continue }
      segments[block.id] = Self.decision(self.segments[index], comparedWith: segments[block.id])
      if self.segments[index].state == .edited {
        editedTexts[block.id] = String(oldTexts[index])
      }
      keptCount += 1
    }
    let newTexts = fresh.texts.texts(of: segments, in: session.blocks, editedTexts: editedTexts)
    for (index, newText) in newTexts.enumerated() {
      segments[index].length = newText.utf16.count
    }

    let switched = ResultDocument(
      session: session, segments: segments, initialSegments: fresh.initialSegments,
      texts: fresh.texts)
    let plan = EditPlan(
      replacements: [TextReplacement(range: 0..<text.utf16.count, text: newTexts.joined())],
      tableChanges: [.document(before: self, after: switched)], isTyping: false)
    return ModeSwitch(plan: plan, discardedDecisionCount: decisionsByLines.count - keptCount)
  }
}

extension Session {
  /// The bytes each input covers in `block`, in the order base, A, B; empty for an input that does
  /// not take part.
  ///
  /// Bytes rather than line numbers identify the same lines across comparison modes, which split
  /// a file at different line endings.
  fileprivate func byteRanges(of block: Block) -> [Range<Int>] {
    Role.allCases.map { files[$0]?.byteRange(ofLines: block.lines(in: $0)) ?? 0..<0 }
  }
}
