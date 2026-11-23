/// How work kept from an earlier session goes into a result as loaded.
public struct WorkRestoration: Sendable {
  /// The plan that puts the work into the result, as a single undo step; empty if no block takes
  /// anything from the work.
  public let plan: EditPlan

  /// The number of blocks whose decision the work holds but that start as loaded, because the
  /// comparison has no block with the same lines in base, A and B.
  ///
  /// It is 0 when every decision and every text typed by hand is back.
  public let restartedBlockCount: Int

  /// The block that was current when the work was captured, if the comparison still has it.
  public let currentBlock: Block?
}

extension ResultDocument {
  /// The plan that restores `work` into this document, if it is as loaded.
  ///
  /// If the blocks are those the work was captured with, the result becomes exactly what it was:
  /// the same text, decisions and text typed by hand, except that open conflicts show the previews
  /// of this document. Otherwise, as after another version of the engine or another merge
  /// strategy, each decision moves to the block with the same lines in base, A and B, as when
  /// switching the comparison mode, together with its text typed by hand; every other block
  /// starts as loaded and is counted in ``WorkRestoration/restartedBlockCount``. Nothing of the
  /// work is dropped without being counted.
  ///
  /// The work sets neither the comparison mode nor the format of the result; the caller compares
  /// the files in ``MergeWork/mode`` before and applies ``MergeWork/format`` itself.
  ///
  /// - Parameter work: Work of a merge of the same files, as ``MergeWork/key`` tells.
  /// - Returns: The restoration, or `nil` if a block of this document already differs from how it
  ///   was after loading, so that restoring would replace what was done since; the work then
  ///   stays as it is.
  public func planRestoring(_ work: MergeWork) -> WorkRestoration? {
    guard !canResetAll else { return nil }
    if work.blockFingerprint == MergeWork.fingerprint(of: session),
      let restoration = planRestoringExactly(work)
    {
      return restoration
    }
    return planRestoringByPlace(work)
  }

  /// The plan that restores `work`, captured with the blocks of this document, segment for
  /// segment, or `nil` if the work does not fit the segments.
  private func planRestoringExactly(_ work: MergeWork) -> WorkRestoration? {
    guard work.segments.count == segments.count else { return nil }
    let keptText = work.text.utf16
    var start = keptText.startIndex
    var text = ""
    var restored = initialSegments
    for (index, saved) in work.segments.enumerated() {
      let block = session.blocks[index]
      if let decision = saved.decision {
        guard takesPart(decision) else { return nil }
        restored[index] = Segment(state: decision.state, sources: decision.sources)
      }
      let segmentText: String
      if restored[index].state == .open {
        guard saved.length == nil else { return nil }
        segmentText = texts.previewText(for: block)
      } else {
        guard let length = saved.length,
          let end = keptText.index(start, offsetBy: length, limitedBy: keptText.endIndex),
          let kept = String(keptText[start..<end])
        else { return nil }
        segmentText = kept
        start = end
      }
      restored[index].length = segmentText.utf16.count
      text += segmentText
    }
    guard start == keptText.endIndex else { return nil }
    let document = ResultDocument(
      session: session, segments: restored, initialSegments: initialSegments, texts: texts)
    let length = segments.reduce(0) { $0 + $1.length }
    let plan = EditPlan(
      replacements: [TextReplacement(range: 0..<length, text: text)],
      tableChanges: [.document(before: self, after: document)], isTyping: false)
    let current = work.currentBlock.flatMap { place in
      session.blocks.indices.contains(place.index) ? session.blocks[place.index] : nil
    }
    return WorkRestoration(plan: plan, restartedBlockCount: 0, currentBlock: current)
  }

  /// The plan that moves each decision of `work` to the block of this document that covers the
  /// same bytes in base, A and B.
  private func planRestoringByPlace(_ work: MergeWork) -> WorkRestoration {
    var blocksByPlace: [[Range<Int>]: Int] = [:]
    for block in session.blocks {
      blocksByPlace[session.byteRanges(of: block)] = block.id
    }
    let keptText = work.text.utf16
    var start = keptText.startIndex
    var decisions: [Int: CarriedDecision] = [:]
    var decidedCount = 0
    for saved in work.segments {
      // The lengths add up to the text, as decoding checks, so each segment finds its text.
      var segmentText: String?
      if let length = saved.length,
        let end = keptText.index(start, offsetBy: length, limitedBy: keptText.endIndex)
      {
        segmentText = String(keptText[start..<end])
        start = end
      }
      guard let decision = saved.decision else { continue }
      decidedCount += 1
      guard let target = blocksByPlace[decision.byteRanges], decisions[target] == nil,
        takesPart(decision)
      else { continue }
      let segment = Segment(state: decision.state, sources: decision.sources)
      if decision.state == .edited {
        guard let segmentText else { continue }
        decisions[target] = CarriedDecision(segment: segment, editedText: segmentText)
      } else {
        decisions[target] = CarriedDecision(segment: segment, editedText: nil)
      }
    }
    let current = work.currentBlock.flatMap { blocksByPlace[$0.byteRanges] }
    return WorkRestoration(
      plan: decisions.isEmpty ? .empty : planCarrying(decisions, to: session),
      restartedBlockCount: decidedCount - decisions.count,
      currentBlock: current.map { session.blocks[$0] })
  }

  /// Whether `decision` can go into a block of this document: it is no open conflict, which only
  /// a conflict as loaded is, and its sources take part in the merge.
  private func takesPart(_ decision: MergeWork.Decision) -> Bool {
    let roles = session.files.roles
    return decision.state != .open && decision.sources.allSatisfy(roles.contains)
  }
}
