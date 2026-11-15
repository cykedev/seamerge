import MergeModel
import Testing

/// Checks that the moves in the scenarios `diff-move` and `merge-move` of
/// `Scripts/make-test-repo.sh` are found, in the strictest mode and in the one a window starts in.
struct MoveScenarioTests {
  @Test(arguments: [ComparisonMode.exact, .ignoreWhitespaceAmount])
  func diffMoveHasAWholeAndAPartialMove(mode: ComparisonMode) async throws {
    let repository = try TestRepository("diff-move")
    defer { repository.remove() }
    let session = try await diff(
      try repository.text(of: "HEAD~1:shapes.swift"), try repository.text(of: "HEAD:shapes.swift"),
      mode: mode)
    let (old, new) = (try session.lineTexts(of: .a), try session.lineTexts(of: .b))

    // The closing brace and the blank line after `area`, which the other functions share, stay
    // with the lines that the engine keeps equal.
    #expect(MovedLinesTests.movedLines(of: session) == [[0..<3, 11..<14], [16..<19, 25..<28]])
    try #require(session.moves.count == 2)
    let (area, describe) = (session.moves[0], session.moves[1])
    #expect(old[area.source.lines] == new[area.destination.lines])
    #expect(old[area.source.lines].first == "func area(of rectangle: Rectangle) -> Double {")
    // `describe` moved with the line that returns changed; the lines before it move, the
    // changed line stays a removal and an addition.
    #expect(old[describe.source.lines].first == "func describe(_ rectangle: Rectangle) -> String {")
    #expect(old[describe.source.lines.upperBound] == "  return width + \" by \" + height")
    #expect(new[describe.destination.lines.upperBound] == "  return width + \" times \" + height")
    #expect(session.blocks.contains { $0.a == 19..<20 && $0.b.isEmpty })
    #expect(session.blocks.contains { $0.a.isEmpty && $0.b == 28..<30 })
  }

  @Test(arguments: [ComparisonMode.exact, .ignoreWhitespaceAmount])
  func mergeMoveExplainsTheConflictWithTheMoveOfA(mode: ComparisonMode) async throws {
    let repository = try TestRepository("merge-move")
    defer { repository.remove() }
    // The stages as `git mergetool` hands them over: A is theirs, B is ours.
    let session = try await merge(
      base: try repository.text(of: ":1:shapes.swift"),
      a: try repository.text(of: ":3:shapes.swift"), b: try repository.text(of: ":2:shapes.swift"),
      mode: mode)

    try #require(session.moves.count == 1)
    let move = session.moves[0]
    let (source, destination) = (
      session.blocks[move.source.block], session.blocks[move.destination.block]
    )
    #expect(move.source.role == .a && move.destination.role == .a)
    #expect(source.kind == .conflict && source.base == 0..<5 && source.a.isEmpty)
    #expect(destination.kind == .changedInA && destination.a == 11..<16)
    let a = try session.lineTexts(of: .a)
    #expect(a[destination.a].first == "func area(of rectangle: Rectangle) -> Double {")
    #expect(try session.lineTexts(of: .b)[source.b].contains("  return product.rounded()"))
  }
}
