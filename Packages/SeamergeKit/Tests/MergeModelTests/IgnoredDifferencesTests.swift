import Foundation
import MergeModel
import Testing

struct IgnoredDifferencesTests {
  @Test func exactModeIgnoresNothing() async throws {
    let session = try await merge(base: "a\nb\n", a: "a\nb  \n", b: "a\nb\n")

    #expect(IgnoredDifferences(in: session).isEmpty)
  }

  @Test func whitespaceChangedOnOneSideMarksOnlyThatSide() async throws {
    let session = try await merge(
      base: "a\nb\nc\n", a: "a\nb  \nc\n", b: "a\nb\nC\n", mode: .ignoreWhitespaceAmount)

    #expect(session.blocks.map(\.kind) == [.unchanged, .changedInB])
    #expect(IgnoredDifferences(in: session).lines(in: .a) == IndexSet(integer: 1))
    #expect(IgnoredDifferences(in: session).lines(in: .base).isEmpty)
    #expect(IgnoredDifferences(in: session).lines(in: .b).isEmpty)
  }

  @Test func sideThatDidNotChangeABlockIsCheckedAgainstTheBase() async throws {
    let session = try await merge(
      base: "a\nz\n", a: "A\nz\n", b: "a \nz\n", mode: .ignoreWhitespaceAmount)

    #expect(session.blocks.first?.kind == .changedInA)
    #expect(IgnoredDifferences(in: session).lines(in: .b) == IndexSet(integer: 0))
    #expect(IgnoredDifferences(in: session).lines(in: .a).isEmpty)
  }

  @Test func sameChangeOnBothSidesChecksAAgainstB() async throws {
    let session = try await merge(
      base: "a\n", a: "b\t\n", b: "b\n", mode: .ignoreWhitespaceAmount)

    #expect(session.blocks.map(\.kind) == [.changedInBoth])
    #expect(IgnoredDifferences(in: session).lines(in: .a) == IndexSet(integer: 0))
    #expect(IgnoredDifferences(in: session).lines(in: .b).isEmpty)
  }

  @Test func changedLineEndingMarksBothFilesOfAComparison() async throws {
    let session = try await diff("x\r\ny\n", "x\ny\n", mode: .ignoreLineEndings)

    #expect(session.blocks.map(\.kind) == [.unchanged])
    #expect(IgnoredDifferences(in: session).lines(in: .a) == IndexSet(integer: 0))
    #expect(IgnoredDifferences(in: session).lines(in: .b) == IndexSet(integer: 0))
  }

  @Test func missingFinalLineEndingIsAnIgnoredDifference() async throws {
    let session = try await diff("x\ny", "x\ny\n", mode: .ignoreLineEndings)

    #expect(session.blocks.map(\.kind) == [.unchanged])
    #expect(IgnoredDifferences(in: session).lines(in: .a) == IndexSet(integer: 1))
  }

  @Test func mergeWithoutABaseChecksAAgainstB() async throws {
    let session = try await merge(
      base: nil, a: "same  \nonly a\n", b: "same\n", mode: .ignoreWhitespaceAmount)

    #expect(IgnoredDifferences(in: session).lines(in: .a) == IndexSet(integer: 0))
    #expect(IgnoredDifferences(in: session).lines(in: .b).isEmpty)
  }

  @Test func conflictLinesAreNeverMarked() async throws {
    let session = try await merge(
      base: "a\n", a: "b \n", b: "c\n", mode: .ignoreWhitespaceAmount)

    #expect(session.blocks.map(\.kind) == [.conflict])
    #expect(IgnoredDifferences(in: session).isEmpty)
  }
}
