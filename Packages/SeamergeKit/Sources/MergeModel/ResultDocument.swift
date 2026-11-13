/// The result of a merge as editable text: one segment for each block, the decision taken in it,
/// and how edits of the text are attributed to the segments.
///
/// The document does not hold the text; the result pane does. The pane reports each edit before
/// carrying it out, and the document answers with an ``EditPlan``: usually the edit itself,
/// sometimes replacements around the preview of a conflict. Commands such as switching a toggle
/// or resetting a block are plans too. Once the pane has carried out a plan, it hands the plan to
/// ``apply(_:replacedTexts:)``, which updates the segments and returns the ``UndoStep``.
///
/// Three rules always hold. Every block of the session has exactly one segment, which may be
/// empty. Choosing sources always works and replaces whatever the segment holds. An open conflict
/// is resolved only by a decision, never by typing beside it.
public struct ResultDocument: Sendable {
  /// The merge whose result this is.
  public let session: Session

  /// The segment of each block, in the order of the blocks.
  public private(set) var segments: [Segment]

  /// The segment of each block after loading.
  let initialSegments: [Segment]

  /// The texts of the inputs.
  let texts: SegmentTexts

  /// Creates the result of `session` as it is after loading.
  ///
  /// A conflict is open and shows its preview. Every other block takes the source the merge
  /// takes for it: the side that changed it, or B where B's text counts as equal to another
  /// side's.
  ///
  /// - Parameter removalNotes: The line that the preview of a conflict shows in place of the
  ///   lines of a side that removed them, such as “A removed these lines”, by side. The note is
  ///   part of the preview, so it is never written. Without a note, the side shows nothing.
  /// - Precondition: The session is a merge, and no note holds a line break.
  public init(session: Session, removalNotes: [Role: String] = [:]) {
    precondition(session.kind == .merge, "Only a merge has a result")
    precondition(
      removalNotes.values.allSatisfy { !$0.contains(where: \.isNewline) },
      "A removal note is a single line")
    let texts = SegmentTexts(
      files: session.files, blocks: session.blocks, removalNotes: removalNotes)
    var segments = session.blocks.map(texts.initialSegment(for:))
    let initialTexts = texts.texts(of: segments, in: session.blocks, editedTexts: [:])
    for (index, text) in initialTexts.enumerated() {
      segments[index].length = text.utf16.count
    }
    self.init(session: session, segments: segments, initialSegments: segments, texts: texts)
  }

  /// Creates a document with the given segments.
  init(session: Session, segments: [Segment], initialSegments: [Segment], texts: SegmentTexts) {
    self.session = session
    self.segments = segments
    self.initialSegments = initialSegments
    self.texts = texts
  }

  /// The text after loading, which the result pane starts with.
  public var initialText: String {
    texts.texts(of: initialSegments, in: session.blocks, editedTexts: [:]).joined()
  }

  /// The segment of a block.
  ///
  /// - Precondition: `block` belongs to the session.
  public func segment(for block: Block) -> Segment {
    segments[index(of: block)]
  }

  /// The range of a block's segment in the text, in UTF-16 code units.
  ///
  /// - Precondition: `block` belongs to the session.
  public func range(of block: Block) -> Range<Int> {
    let start = segments[..<index(of: block)].reduce(0) { $0 + $1.length }
    return start..<start + segments[block.id].length
  }

  /// The toggles of a block, one for each different text, ordered by their first input.
  ///
  /// A toggle is switched on if the sources of the block's segment include its inputs.
  ///
  /// - Precondition: `block` belongs to the session.
  public func toggles(in block: Block) -> [Toggle] {
    texts.toggles(in: session.blocks[index(of: block)])
  }

  /// The preview of a conflict: A's lines, then B's lines, each ending with a line ending; a side
  /// that removed the lines shows its removal note instead.
  ///
  /// The preview is what the segment of an open conflict holds. It is not part of the file and is
  /// never written; conflict markers take its place.
  ///
  /// - Precondition: `block` is a conflict of the session.
  public func previewText(for block: Block) -> String {
    precondition(block.kind == .conflict, "Block \(block.id) is not a conflict")
    return texts.previewText(for: session.blocks[index(of: block)])
  }

  /// The number of lines that the preview of a conflict shows for `role`, A or B: its lines, or
  /// one for its removal note.
  ///
  /// - Precondition: `block` is a conflict of the session.
  public func previewLineCount(of role: Role, in block: Block) -> Int {
    precondition(block.kind == .conflict, "Block \(block.id) is not a conflict")
    let block = session.blocks[index(of: block)]
    let lineCount = block.lines(in: role).count
    return lineCount == 0 && !texts.previewPart(of: role, in: block).isEmpty ? 1 : lineCount
  }

  /// The number of conflicts that await a decision.
  public var openConflictCount: Int {
    segments.count { $0.state == .open }
  }

  /// Takes over a plan that the result pane has carried out.
  ///
  /// - Parameters:
  ///   - plan: A plan of this document, made for its current segments.
  ///   - replacedTexts: The text each replacement of the plan replaced, in the same order.
  /// - Returns: The step that undoes the plan.
  @discardableResult
  public mutating func apply(_ plan: EditPlan, replacedTexts: [String]) -> UndoStep {
    precondition(
      replacedTexts.count == plan.replacements.count, "Each replacement needs its replaced text")
    for change in plan.tableChanges {
      switch change {
      case .segment(let index, let before, let after):
        precondition(segments[index] == before, "The plan was made for another segment \(index)")
        segments[index] = after
      case .document(_, let after):
        self = after
      }
    }
    let replacements = zip(plan.replacements, replacedTexts).map { replacement, replacedText in
      precondition(
        replacedText.utf16.count == replacement.range.count,
        "The replaced text does not fill the replaced range")
      return UndoStep.Replacement(
        range: replacement.range, replacedText: replacedText, text: replacement.text)
    }
    return UndoStep(
      replacements: replacements, tableChanges: plan.tableChanges, isTyping: plan.isTyping)
  }

  /// The index of the segment of `block`.
  ///
  /// - Precondition: `block` belongs to the session, not to an earlier comparison of its files.
  func index(of block: Block) -> Int {
    precondition(
      session.blocks.indices.contains(block.id) && session.blocks[block.id] == block,
      "Block \(block.id) is not a block of the session")
    return block.id
  }

  /// The offset where each segment starts, followed by the length of the text.
  func segmentStarts() -> [Int] {
    var starts = [0]
    starts.reserveCapacity(segments.count + 1)
    for segment in segments {
      starts.append(starts[starts.count - 1] + segment.length)
    }
    return starts
  }

  /// The text of each segment, cut from `text`.
  ///
  /// - Precondition: `text` is the result text, as long as the segments together.
  func split(_ text: String) -> [Substring] {
    let utf16 = text.utf16
    precondition(
      utf16.count == segments.reduce(0) { $0 + $1.length }, "The text does not fit the segments")
    var start = text.startIndex
    return segments.map { segment in
      let end = utf16.index(start, offsetBy: segment.length)
      defer { start = end }
      return text[start..<end]
    }
  }

  /// A plan that gives segments a new decision and the text that follows from it.
  ///
  /// A segment that already has the same decision keeps its text. Choosing exactly the sources a
  /// block was loaded with returns it to its loaded state, untouched or automatic, so that there
  /// is nothing to reset.
  ///
  /// - Parameter decisions: The new segment for each index; its length is ignored, and it is not
  ///   edited.
  func planRewriting(_ decisions: [Int: Segment]) -> EditPlan {
    let starts = segmentStarts()
    var after = segments
    var replacements: [Int: TextReplacement] = [:]
    for (index, choice) in decisions {
      let decision = Self.decision(choice, comparedWith: initialSegments[index])
      guard !segments[index].hasSameDecision(as: decision) else { continue }
      let text = texts.text(of: decision, in: session.blocks[index], followedByText: false)
      after[index] = Segment(
        length: text.utf16.count, state: decision.state, sources: decision.sources)
      replacements[index] = TextReplacement(range: starts[index]..<starts[index + 1], text: text)
    }
    endTextsWithoutLineEnding(in: &after, replacements: &replacements, starts: starts)

    // From the last segment to the first, so that each replacement leaves the ranges of those
    // still to come as they were; a line ending added at the end of a segment then also lands
    // before the new text of an empty segment that follows it.
    let indices = replacements.keys.sorted()
    return EditPlan(
      replacements: indices.reversed().compactMap { replacements[$0] },
      tableChanges: indices.map { .segment(index: $0, before: segments[$0], after: after[$0]) },
      isTyping: false)
  }

  /// `decision`, or `initial` if the decision chooses exactly the sources of a block that is no
  /// conflict as it was loaded, which returns the block to its loaded state, untouched or
  /// automatic.
  static func decision(_ decision: Segment, comparedWith initial: Segment) -> Segment {
    decision.state == .chosen && initial.state != .open && decision.sources == initial.sources
      ? initial : decision
  }

  /// Adds a line ending after each text from the inputs that ends without one, because it holds
  /// the last line of a file, while text follows it, and removes it once no text follows, as the
  /// engine joins texts.
  ///
  /// - Parameters:
  ///   - after: The segments after the plan, whose lengths change with the line endings.
  ///   - replacements: The replacement of each segment; a segment that has one so far gets its
  ///     whole text from it.
  ///   - starts: Where each segment starts before the plan.
  private func endTextsWithoutLineEnding(
    in after: inout [Segment], replacements: inout [Int: TextReplacement], starts: [Int]
  ) {
    let lineEnding = texts.lineEnding
    let lastText = after.lastIndex { $0.length > 0 } ?? -1
    for index in texts.blocksEndingWithoutLineEnding {
      guard [.untouched, .auto, .chosen].contains(after[index].state) else { continue }
      let text =
        replacements[index]?.text
        ?? texts.text(of: after[index], in: session.blocks[index], followedByText: false)
      guard !text.isEmpty, !SegmentTexts.endsWithLineEnding(text) else { continue }
      let isFollowedByText = lastText > index
      let end = starts[index + 1]
      if replacements[index] != nil {
        guard isFollowedByText else { continue }
        replacements[index]?.text += lineEnding
      } else if isFollowedByText && segments[index].length == text.utf16.count {
        replacements[index] = TextReplacement(range: end..<end, text: lineEnding)
      } else if !isFollowedByText && segments[index].length > text.utf16.count {
        replacements[index] = TextReplacement(
          range: end - lineEnding.utf16.count..<end, text: "")
      } else {
        continue
      }
      after[index].length = text.utf16.count + (isFollowedByText ? lineEnding.utf16.count : 0)
    }
  }
}
