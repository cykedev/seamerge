import Foundation
import MergeEngine
import MergeModel
import Testing

struct ExportTests {
  static let labels = ConflictLabels(a: "feature/login", base: "a1b2c3d", b: "main")

  @Test(arguments: zip(ComparisonMode.allCases, [UInt64(1), 2, 3, 4]))
  func resultWithoutHandEditsHasTheBytesAndBlockRangesOfTheEngine(
    mode: ComparisonMode, seed: UInt64
  ) async throws {
    var generator = SplitMix64(seed: seed)
    for run in 0..<300 {
      let input = RandomMergeInput(using: &generator)
      let strategy = MergeModel.MergeStrategy.allCases.randomElement(using: &generator) ?? .optimal
      var buffer = ResultBuffer(try await input.session(mode: mode, strategy: strategy))
      let engine = try input.engineMerge(mode: mode, strategy: strategy)
      try #require(engine.blocks.count == buffer.blocks.count)

      var resolutions: [Int: Merge.Source] = [:]
      for block in buffer.blocks where block.kind == .conflict || Bool.random(using: &generator) {
        let (source, roles) = Self.randomChoice(in: block, of: buffer.document, using: &generator)
        resolutions[block.id] = source
        buffer.perform(buffer.document.planChoosing(roles, in: block))
      }

      let output = try #require(engine.result(resolutions: resolutions))
      let context = Comment(rawValue: "seed \(seed), run \(run), \(input), \(resolutions)")
      #expect(Data(buffer.text.utf8) == output.data, context)
      #expect(Self.byteRanges(of: buffer) == output.blockRanges, context)
      #expect(buffer.document.exportText(of: buffer.text, labels: Self.labels) == buffer.text)
    }
  }

  @Test(arguments: zip(ComparisonMode.allCases, [UInt64(5), 6, 7, 8]))
  func exportWithOpenConflictsHasTheBytesOfTheEnginesDiff3Markers(
    mode: ComparisonMode, seed: UInt64
  ) async throws {
    var generator = SplitMix64(seed: seed)
    for run in 0..<300 {
      let input = RandomMergeInput(using: &generator)
      var buffer = ResultBuffer(try await input.session(mode: mode, strategy: .optimal))
      let engine = try input.engineMerge(mode: mode, strategy: .optimal)

      var resolutions: [Int: Merge.Source] = [:]
      for block in buffer.blocks where Bool.random(using: &generator) {
        let (source, roles) = Self.randomChoice(in: block, of: buffer.document, using: &generator)
        resolutions[block.id] = source
        buffer.perform(buffer.document.planChoosing(roles, in: block))
      }

      let output = engine.result(
        markingConflicts: .diff3,
        labels: Merge.ConflictLabels(
          a: Self.labels.a, base: Self.labels.base, b: Self.labels.b),
        resolutions: resolutions)
      let exported = buffer.document.exportText(of: buffer.text, labels: Self.labels)
      #expect(
        Data(exported.utf8) == output.data,
        "seed \(seed), run \(run), \(input), \(resolutions)")
    }
  }

  @Test func markersAreWrittenInTheOrderBBaseAAsGitWritesAndReadsThem() async throws {
    let base = "u\nx\nv\n"
    let a = "u\na\nv\n"
    let b = "u\nb\nv\n"
    let document = ResultDocument(session: try await merge(base: base, a: a, b: b))

    let exported = document.exportText(of: document.initialText, labels: Self.labels)

    #expect(
      exported == "u\n<<<<<<< main\nb\n||||||| a1b2c3d\nx\n=======\na\n>>>>>>> feature/login\nv\n")
    let merged = try Git.run(
      [
        "merge-file", "-p", "--diff3", "-L", "main", "-L", "a1b2c3d", "-L", "feature/login",
        "b", "base", "a",
      ],
      files: ["base": base, "a": a, "b": b])
    #expect(merged.output == exported)
    let check = try Git.run(
      ["diff", "--no-index", "--check", "empty", "exported"],
      files: ["empty": "", "exported": exported])
    #expect(check.output.components(separatedBy: "leftover conflict marker").count - 1 == 4)
  }

  @Test func markerStartsALineAfterTheLineEndingBeforeAPreviewWasDeleted() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    buffer.type("", replacing: 8..<9)

    let exported = buffer.document.exportText(of: buffer.text, labels: Self.labels)

    #expect(exported.hasPrefix("u0\nA1\nu2\n<<<<<<< main\nB3\n"))
    let check = try Git.run(
      ["diff", "--no-index", "--check", "empty", "exported"],
      files: ["empty": "", "exported": exported])
    #expect(check.output.components(separatedBy: "leftover conflict marker").count - 1 == 8)
  }

  @Test func lineEndingFollowsALastLineWithoutOneOnlyWhileTextFollowsIt() async throws {
    let session = try await merge(
      base: "p\nq\n", a: "p\nq", b: "p\nq\nr\n", mode: .ignoreLineEndings)
    try #require(session.blocks.map(\.kind) == [.unchanged, .changedInB])
    var buffer = ResultBuffer(session)

    buffer.perform(buffer.document.planChoosing([.a], in: buffer.blocks[0]))
    #expect(buffer.text == "p\nq\nr\n")

    buffer.perform(buffer.document.planChoosing([.base], in: buffer.blocks[1]))
    #expect(buffer.text == "p\nq")

    buffer.perform(buffer.document.planResetting(buffer.blocks[1]))
    #expect(buffer.text == "p\nq\nr\n")
    buffer.checkInvariants()
  }

  @Test func fileWhoseLinesEndInCRKeepsThemInTheResult() async throws {
    let session = try await merge(base: "u\rx\r", a: "u\ra\r", b: "u\rx\r")
    let buffer = ResultBuffer(session)

    #expect(buffer.text == "u\ra\r")
  }

  /// A source for `block` that the engine can express, and the roles that choose it.
  private static func randomChoice(
    in block: Block, of document: ResultDocument, using generator: inout SplitMix64
  ) -> (Merge.Source, [Role]) {
    var choices: [(Merge.Source, [Role])] = [(.a, [.a]), (.b, [.b])]
    if document.session.roles.contains(.base) {
      choices.append((.base, [.base]))
    }
    // A sequence of two toggles is the concatenation the engine writes only if they differ and
    // neither is exclusive.
    let toggles = document.toggles(in: block)
    if let toggleA = toggles.first(where: { $0.roles.contains(.a) }),
      let toggleB = toggles.first(where: { $0.roles.contains(.b) }),
      toggleA != toggleB, !toggleA.isExclusive, !toggleB.isExclusive
    {
      choices += [(.aThenB, [.a, .b]), (.bThenA, [.b, .a])]
    }
    return choices.randomElement(using: &generator) ?? (.b, [.b])
  }

  /// The UTF-8 byte range of each block's segment.
  private static func byteRanges(of buffer: ResultBuffer) -> [Range<Int>] {
    var start = 0
    return buffer.segmentTexts.map { text in
      defer { start += text.utf8.count }
      return start..<start + text.utf8.count
    }
  }
}
