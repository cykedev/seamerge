import MergeModel
import Testing

struct LineEndingTests {
  @Test func fileEndingEveryLineInCRMatchesTheSameFileWithLFInExactMode() async throws {
    let session = try await diff("one\rtwo\rthree\r", "one\ntwo\nthree\n")

    #expect(session.blocks.map(\.kind) == [.unchanged])
    #expect(session.rowLayout.lineCount(in: .a) == 3)
    #expect(try session.rowTexts(of: .a) == ["one", "two", "three"])
  }

  @Test func changedLineOfAFileEndingInCRIsTheOnlyChangedBlock() async throws {
    let session = try await diff("one\rtwo\rthree\r", "one\rTWO\rthree\r")

    #expect(session.blocks.map(\.kind) == [.unchanged, .changed, .unchanged])
    let changed = try #require(session.blocks.first { $0.kind == .changed })
    #expect(changed.a == 1..<2)
    #expect(changed.b == 1..<2)
  }

  @Test func convertedLinesMapToRowsAndBack() async throws {
    let session = try await merge(
      base: "a\rb\rc\rd\re\r", a: "a\nb\nc\nnew\nd\ne\n", b: "a\rB\rc\rd\re")
    let layout = session.rowLayout

    #expect(
      session.blocks.map(\.kind) == [
        .unchanged, .changedInB, .unchanged, .changedInA, .unchanged, .changedInB,
      ])
    for role in session.roles {
      let shown = (0..<layout.rowCount).compactMap { layout.line(atRow: $0, in: role) }
      #expect(shown == Array(0..<layout.lineCount(in: role)))
      for line in shown {
        #expect(layout.line(atRow: layout.row(ofLine: line, in: role), in: role) == line)
      }
    }
    #expect(try session.rowTexts(of: .b) == ["a", "B", "c", "", "d", "e"])
    #expect(try session.rowTexts(of: .base) == ["a", "b", "c", "", "d", "e"])
  }

  @Test func fileKeepsItsLineEndingsWhenItIsCompared() async throws {
    let session = try await diff("one\rtwo\r", "one\ntwo\n")

    #expect(session.file(for: .a)?.text == "one\rtwo\r")
    #expect(session.file(for: .a)?.lineEndingStyle == .uniform(.cr))
  }

  @Test func loneCarriageReturnInAFileWithOtherLineEndingsStaysVisible() async throws {
    let session = try await diff("x\r\ny\rz\r\n", "x\r\nyz\r\n")

    #expect(session.file(for: .a)?.lineEndingStyle?.isMixed == true)
    #expect(try session.rowTexts(of: .a) == ["x", "y\u{240D}z"])
  }

  @Test func modesThatIgnoreLineEndingsSplitAtCRWithoutConversion() async throws {
    let session = try await diff("one\rtwo\r", "one\ntwo\n", mode: .ignoreLineEndings)

    #expect(session.blocks.map(\.kind) == [.unchanged])
    #expect(try session.rowTexts(of: .a) == ["one", "two"])
  }

  @Test func sessionTellsWhetherTheLineEndingsOfTheFilesDiffer() async throws {
    #expect(try await diff("a\rb\r", "a\nb\n").lineEndingsDiffer)
    #expect(try await diff("a\r\n", "a\n\r\n").lineEndingsDiffer)
    #expect(try await !diff("a\r\nb\r\n", "c\r\n").lineEndingsDiffer)
    #expect(try await !diff("a\nb\r\n", "a\rb\n").lineEndingsDiffer)
    #expect(try await !merge(base: "a", a: "a\n", b: "b\n").lineEndingsDiffer)
  }
}
