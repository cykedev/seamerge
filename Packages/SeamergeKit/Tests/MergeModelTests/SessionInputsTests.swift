import Foundation
import MergeModel
import Testing

struct SessionInputsTests {
  private struct Failure: Error, Equatable {
    var role: Role
  }

  @Test func inputsWithABaseListAllThreeInTheOrderBaseAB() {
    let inputs = Session.Inputs(base: "base", a: "a", b: "b")

    #expect(inputs.roles == [.base, .a, .b])
    #expect(inputs.values == ["base", "a", "b"])
    #expect(inputs.map(\.role) == [.base, .a, .b])
    #expect(inputs.map(\.value) == ["base", "a", "b"])
    #expect(Role.allCases.map { inputs[$0] } == ["base", "a", "b"])
  }

  @Test func inputsWithoutABaseHaveOnlyAAndB() {
    let inputs = Session.Inputs(a: "a", b: "b")

    #expect(inputs.roles == [.a, .b])
    #expect(inputs.values == ["a", "b"])
    #expect(inputs.map(\.role) == [.a, .b])
    #expect(inputs[.base] == nil)
    #expect(inputs[.a] == "a")
    #expect(inputs[.b] == "b")
  }

  @Test func mappingKeepsTheBaseOnlyWhereThereIsOne() {
    let withBase = Session.Inputs(base: "base", a: "a", b: "bb").mapValues(\.count)
    let withoutBase = Session.Inputs(a: "a", b: "bb").mapValues(\.count)

    #expect(withBase == Session.Inputs(base: 4, a: 1, b: 2))
    #expect(withoutBase == Session.Inputs(a: 1, b: 2))
  }

  @Test func mappingWithRolesHandsEachValueItsRole() {
    let inputs = Session.Inputs(base: 0, a: 1, b: 2).mapValuesWithRoles { role, value in
      "\(role) \(value)"
    }

    #expect(inputs == Session.Inputs(base: "base 0", a: "a 1", b: "b 2"))
  }

  @Test func mappingRunsInTheOrderBaseABAndStopsAtTheFirstError() {
    var visited: [Role] = []

    #expect(throws: Failure(role: .a)) {
      try Session.Inputs(base: Role.base, a: .a, b: .b).mapValues { role throws(Failure) in
        visited.append(role)
        guard role != .a else { throw Failure(role: role) }
        return role
      }
    }
    #expect(visited == [.base, .a])
  }

  @Test func aSessionHasTheInputsItWasMadeOf() async throws {
    let merge = try await Session.merge(
      base: SourceFile(bytes: Data("base\n".utf8), label: "base"),
      a: SourceFile(bytes: Data("a\n".utf8), label: "a"),
      b: SourceFile(bytes: Data("b\n".utf8), label: "b"))
    let twoWay = try await Session.merge(
      base: nil, a: SourceFile(bytes: Data("a\n".utf8), label: "a"),
      b: SourceFile(bytes: Data("b\n".utf8), label: "b"))
    let diff = try await Session.diff(
      old: SourceFile(bytes: Data("old\n".utf8), label: "old"),
      new: SourceFile(bytes: Data("new\n".utf8), label: "new"))

    #expect(merge.inputs.mapValues(\.label) == Session.Inputs(base: "base", a: "a", b: "b"))
    #expect(twoWay.inputs.mapValues(\.label) == Session.Inputs(a: "a", b: "b"))
    #expect(diff.inputs.mapValues(\.label) == Session.Inputs(a: "old", b: "new"))
  }
}
