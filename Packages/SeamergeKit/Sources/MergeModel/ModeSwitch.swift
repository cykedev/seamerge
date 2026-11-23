import Foundation

/// The switch of a result to a new comparison: of the same files in another comparison mode or
/// with another merge strategy, or of the files as they are now after one changed on disk.
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
    var decisionsByLines: [[Range<Int>]: Int] = [:]
    for index in segments.indices where differsFromInitial(index) {
      decisionsByLines[self.session.byteRanges(of: self.session.blocks[index])] = index
    }
    var matches: [Int: Int] = [:]
    for block in session.blocks {
      matches[block.id] = decisionsByLines[session.byteRanges(of: block)]
    }
    return plan(carrying: matches, decidedCount: decisionsByLines.count, to: session, text: text)
  }

  /// The switch to `session`, a merge of the files of this document's session as they are after
  /// one or more of them changed on disk, keeping each decision whose block is still there, at
  /// the same place.
  ///
  /// A decision moves only to the block that covers, in base, A and B, the same lines as before,
  /// shifted by the lines added or removed before them, and that has exactly the same text in
  /// each. Text typed by hand moves with its block. A block with the same text elsewhere does not
  /// count: every decision that cannot move to its own place is discarded and counted, so that
  /// the window can ask first.
  ///
  /// - Parameters:
  ///   - session: A merge of the files of this document's session after they changed, in the
  ///     same comparison mode.
  ///   - text: The result text, as long as the segments together.
  public func planReloading(to session: Session, text: String) -> ModeSwitch {
    let old = self.session
    let shifts = Dictionary(
      uniqueKeysWithValues: Role.allCases.map { role in
        (role, LineShift(from: old.files[role], to: session.files[role], mode: old.options.mode))
      })
    var blocksByPlace: [[Range<Int>]: Int] = [:]
    for block in session.blocks {
      blocksByPlace[Role.allCases.map(block.lines(in:))] = block.id
    }
    var matches: [Int: Int] = [:]
    let decided = segments.indices.filter(differsFromInitial)
    for index in decided {
      let block = old.blocks[index]
      let place = Role.allCases.compactMap { shifts[$0]?.place(of: block.lines(in: $0)) }
      guard place.count == Role.allCases.count, let target = blocksByPlace[place],
        old.texts(of: block) == session.texts(of: session.blocks[target])
      else { continue }
      matches[target] = index
    }
    return plan(carrying: matches, decidedCount: decided.count, to: session, text: text)
  }

  /// The switch to `session` that gives each block of it the decision of the block of this
  /// document that `matches` names, and every other block its loaded state.
  ///
  /// - Parameters:
  ///   - matches: The index of a decided block of this document for each block of `session`
  ///     that takes over its decision.
  ///   - decidedCount: How many blocks of this document have a decision.
  private func plan(
    carrying matches: [Int: Int], decidedCount: Int, to session: Session, text: String
  ) -> ModeSwitch {
    let oldTexts = split(text)
    var decisions: [Int: CarriedDecision] = [:]
    for (id, index) in matches {
      let segment = segments[index]
      decisions[id] = CarriedDecision(
        segment: segment, editedText: segment.state == .edited ? String(oldTexts[index]) : nil)
    }
    return ModeSwitch(
      plan: planCarrying(decisions, to: session),
      discardedDecisionCount: decidedCount - matches.count)
  }

  /// The plan that replaces the result with that of `session`, in which each block that
  /// `decisions` names takes its decision and every other block its loaded state.
  ///
  /// A decision that takes the sources the block is loaded with leaves it untouched or automatic.
  /// The plan replaces the whole text and the whole document in a single step.
  ///
  /// - Parameters:
  ///   - decisions: The decision for each block of `session` that takes one, by its position.
  ///   - session: A merge of the files of this document's session.
  func planCarrying(_ decisions: [Int: CarriedDecision], to session: Session) -> EditPlan {
    let fresh = ResultDocument(session: session, removalNotes: texts.removalNotes)
    var segments = fresh.segments
    var editedTexts: [Int: String] = [:]
    for (id, decision) in decisions {
      segments[id] = Self.decision(decision.segment, comparedWith: segments[id])
      if decision.segment.state == .edited {
        guard let text = decision.editedText else {
          preconditionFailure("Edited decision for block \(id) has no text")
        }
        editedTexts[id] = text
      }
    }
    let newTexts = fresh.texts.texts(of: segments, in: session.blocks, editedTexts: editedTexts)
    for (index, newText) in newTexts.enumerated() {
      segments[index].length = newText.utf16.count
    }

    let switched = ResultDocument(
      session: session, segments: segments, initialSegments: fresh.initialSegments,
      texts: fresh.texts)
    let length = self.segments.reduce(0) { $0 + $1.length }
    return EditPlan(
      replacements: [TextReplacement(range: 0..<length, text: newTexts.joined())],
      tableChanges: [.document(before: self, after: switched)], isTyping: false)
  }
}

/// A decision that moves from a block of one result to a block of another: the segment of the
/// block and, if the segment was edited by hand, its text.
struct CarriedDecision {
  /// The segment, whose length does not count.
  let segment: Segment

  /// The text of an edited segment; `nil` for any other.
  let editedText: String?
}

/// Where the lines of an input went after it changed on disk: the runs of lines that stayed, as
/// a comparison of the input before and after finds them.
private struct LineShift {
  /// A run of lines that stayed: where it was, and the line it starts at now.
  private struct Run {
    let old: Range<Int>
    let newStart: Int
  }

  /// The runs that stayed, or `nil` for an input that did not change at all.
  private let runs: [Run]?

  /// The places of the lines of `old`, the input before, in `new`, the input after, compared in
  /// `mode`; an input that takes no part stays empty.
  init(from old: ComparedFile?, to new: ComparedFile?, mode: ComparisonMode) {
    guard let old, let new, old.utf8 != new.utf8 else {
      runs = nil
      return
    }
    let comparison: EngineAdapter.Comparison
    do {
      comparison = try EngineAdapter.diff(old: old.utf8, new: new.utf8, mode: mode)
    } catch {
      // Without a comparison no line has a certain place; every decision is then counted as
      // discarded, which the window asks about.
      runs = []
      return
    }
    // Lines must be split as the sessions split them, or no place is certain.
    guard comparison.lineStarts.a == old.lineStarts, comparison.lineStarts.b == new.lineStarts
    else {
      runs = []
      return
    }
    runs = comparison.blocks.filter { $0.kind == .unchanged }.map {
      Run(old: $0.a, newStart: $0.b.lowerBound)
    }
  }

  /// Where `lines` of the input before are now, or `nil` if they did not stay as they were, or
  /// if an empty range lies where lines were added, so that its place is in doubt.
  func place(of lines: Range<Int>) -> Range<Int>? {
    guard let runs else { return lines }
    if lines.isEmpty {
      let places = Set(
        runs.filter {
          $0.old.lowerBound <= lines.lowerBound && lines.lowerBound <= $0.old.upperBound
        }
        .map { $0.newStart + lines.lowerBound - $0.old.lowerBound })
      return places.count == 1 ? places.first.map { $0..<$0 } : nil
    }
    guard
      let run = runs.first(where: {
        $0.old.lowerBound <= lines.lowerBound && lines.upperBound <= $0.old.upperBound
      })
    else { return nil }
    let start = run.newStart + lines.lowerBound - run.old.lowerBound
    return start..<(start + lines.count)
  }
}

extension Session {
  /// The texts of the lines each input covers in `block`, in the order base, A, B; empty for an
  /// input that does not take part.
  fileprivate func texts(of block: Block) -> [Data] {
    Role.allCases.map { role in
      files[role].map { $0.utf8[$0.byteRange(ofLines: block.lines(in: role))] } ?? Data()
    }
  }

  /// The bytes each input covers in `block`, in the order base, A, B; empty for an input that does
  /// not take part.
  ///
  /// Bytes rather than line numbers identify the same lines across comparison modes, which split
  /// a file at different line endings.
  func byteRanges(of block: Block) -> [Range<Int>] {
    Role.allCases.map { files[$0]?.byteRange(ofLines: block.lines(in: $0)) ?? 0..<0 }
  }
}
