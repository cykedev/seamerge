import MergeModel
import Testing

struct ModeSwitchTests {
  /// Inputs of seven blocks in every mode.
  ///
  /// The blocks are unchanged, changed in A, unchanged, a conflict, unchanged, changed in B,
  /// unchanged. A also adds a trailing space to line 2, which belongs to
  /// block 1 in the exact mode and to block 2 when the amount of whitespace is ignored.
  static let base = "u0\nx1\nw2\nu3\nx4\nu5\nx6\nu7\n"
  static let a = "u0\nA1\nw2 \nu3\nA4\nu5\nx6\nu7\n"
  static let b = "u0\nx1\nw2\nu3\nB4\nu5\nB6\nu7\n"
  static let kinds: [Block.Kind] = [
    .unchanged, .changedInA, .unchanged, .conflict, .unchanged, .changedInB, .unchanged,
  ]

  @Test func recomputingComparesTheSameFilesWithTheNewOptions() async throws {
    let exact = try await merge(base: Self.base, a: Self.a, b: Self.b)

    let lenient = try await exact.recomputed(
      options: ComparisonOptions(mode: .ignoreWhitespaceAmount))

    #expect(lenient.kind == .merge)
    #expect(lenient.options.mode == .ignoreWhitespaceAmount)
    #expect(lenient.file(for: .a)?.text == Self.a)
    #expect(lenient.blocks.map(\.kind) == Self.kinds)
    #expect(lenient.blocks[1].a == 1..<2)
    #expect(exact.blocks[1].a == 1..<3)
  }

  @Test func switchingKeepsDecisionsInBlocksWithTheSameLinesAndCountsTheOthers() async throws {
    let exact = try await merge(base: Self.base, a: Self.a, b: Self.b)
    try #require(exact.blocks.map(\.kind) == Self.kinds)
    var buffer = ResultBuffer(exact)
    buffer.perform(buffer.document.planChoosing([.b], in: buffer.blocks[1]))
    buffer.perform(buffer.document.planChoosing([.a, .b], in: buffer.blocks[3]))
    buffer.type("hand ", at: buffer.document.range(of: buffer.blocks[5]).lowerBound)
    let lenient = try await exact.recomputed(
      options: ComparisonOptions(mode: .ignoreWhitespaceAmount))

    let modeSwitch = buffer.document.planSwitching(to: lenient, text: buffer.text)
    buffer.perform(modeSwitch.plan)

    #expect(modeSwitch.discardedDecisionCount == 1)
    #expect(buffer.document.session.options.mode == .ignoreWhitespaceAmount)
    #expect(
      buffer.segmentTexts == ["u0\n", "A1\n", "w2\nu3\n", "A4\nB4\n", "u5\n", "hand B6\n", "u7\n"])
    #expect(
      buffer.document.segments.map(\.state) == [
        .untouched, .auto, .untouched, .chosen, .untouched, .edited, .untouched,
      ])
    buffer.checkInvariants()
  }

  @Test func switchingIsOneUndoStepThatBringsBackTheOldSession() async throws {
    let exact = try await merge(base: Self.base, a: Self.a, b: Self.b)
    var buffer = ResultBuffer(exact)
    buffer.perform(buffer.document.planChoosing([.b], in: buffer.blocks[1]))
    let text = buffer.text
    let segments = buffer.document.segments
    let lenient = try await exact.recomputed(
      options: ComparisonOptions(mode: .ignoreWhitespaceAmount))
    buffer.perform(buffer.document.planSwitching(to: lenient, text: buffer.text).plan)

    buffer.undo()

    #expect(buffer.document.session.options.mode == .exact)
    #expect(buffer.text == text)
    #expect(buffer.document.segments == segments)
    buffer.redo()
    #expect(buffer.document.session.options.mode == .ignoreWhitespaceAmount)
    #expect(buffer.document.segments[1].state == .auto)
  }

  @Test func switchingWithoutDecisionsDiscardsNone() async throws {
    let exact = try await merge(base: Self.base, a: Self.a, b: Self.b)
    let document = ResultDocument(session: exact)
    let lenient = try await exact.recomputed(options: ComparisonOptions(mode: .ignoreAllWhitespace))

    let modeSwitch = document.planSwitching(to: lenient, text: document.initialText)

    #expect(modeSwitch.discardedDecisionCount == 0)
    #expect(
      modeSwitch.plan.replacements.map(\.text) == [ResultDocument(session: lenient).initialText])
  }

  @Test func sameLinesAreRecognizedByTheirBytesWhereALoneCRSplitsLinesDifferently() async throws {
    // The exact mode ends lines only at LF, so line numbers after the lone CR differ by one.
    let exact = try await merge(base: "c\rd\nx\n", a: "c\rd\na\n", b: "c\rd\nb\n")
    let lenient = try await exact.recomputed(options: ComparisonOptions(mode: .ignoreLineEndings))
    try #require(exact.blocks.map(\.kind) == [.unchanged, .conflict])
    try #require(lenient.blocks.map(\.kind) == [.unchanged, .conflict])
    try #require(exact.blocks[1].a != lenient.blocks[1].a)
    var buffer = ResultBuffer(exact)
    buffer.perform(buffer.document.planChoosing([.a, .b], in: buffer.blocks[1]))

    let modeSwitch = buffer.document.planSwitching(to: lenient, text: buffer.text)
    buffer.perform(modeSwitch.plan)

    #expect(modeSwitch.discardedDecisionCount == 0)
    #expect(buffer.text == "c\rd\na\nb\n")
    #expect(buffer.document.segments[1].state == .chosen)
  }

  @Test func keptDecisionThatTakesTheSourcesTheNewBlockLoadsWithIsAutomatic() async throws {
    // A conflict in the exact mode is unchanged when all whitespace is ignored, and takes B.
    let exact = try await merge(base: "x\n", a: "x\r\n", b: " x\n")
    let lenient = try await exact.recomputed(options: ComparisonOptions(mode: .ignoreAllWhitespace))
    try #require(exact.blocks.map(\.kind) == [.conflict])
    try #require(lenient.blocks.map(\.kind) == [.unchanged])
    var buffer = ResultBuffer(exact)
    buffer.perform(buffer.document.planChoosing([.b], in: buffer.blocks[0]))

    let modeSwitch = buffer.document.planSwitching(to: lenient, text: buffer.text)
    buffer.perform(modeSwitch.plan)

    #expect(modeSwitch.discardedDecisionCount == 0)
    #expect(buffer.document.segments[0].state == .untouched)
    #expect(!buffer.document.canResetAll)
    #expect(buffer.text == " x\n")
  }

  @Test func blockOfAnEarlierComparisonIsNoBlockOfTheDocument() async {
    await #expect(processExitsWith: .failure) {
      let exact = try await merge(base: Self.base, a: Self.a, b: Self.b)
      let lenient = try await exact.recomputed(
        options: ComparisonOptions(mode: .ignoreWhitespaceAmount))
      _ = ResultDocument(session: lenient).range(of: exact.blocks[1])
    }
  }
}
