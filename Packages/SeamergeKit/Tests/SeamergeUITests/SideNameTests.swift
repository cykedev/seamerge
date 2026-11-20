import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The name that sentences give a side, such as "main removed these lines": the name from Git or
/// the command line, else the file name where it tells the sides apart, else the letter.
@MainActor
@Suite struct SideNameTests {
  @Test func nameFromGitNamesTheSide() async throws {
    let (session, context) = try await Scenario.merges[0].load()
    let a = try #require(SideHeader.headers(of: session, context: context)[.a])
    #expect(a.distinctName == "feature")
    #expect(a.distinctName == a.name)
  }

  @Test func fileNamesThatDifferNameTheSides() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    let headers = controller.presentation.headers
    #expect(
      [Role.base, .a, .b].map { headers[$0]?.distinctName } == ["base.txt", "a.txt", "b.txt"])
    #expect(try Self.preview(ofBlock: 3, in: controller).contains("a.txt removed these lines"))
  }

  @Test func sidesWhoseFilesShareANameAreNamedByTheirLetters() async throws {
    let session = try await Session.merge(
      base: SourceFile(bytes: Data("u0\nx1\nu2\nx3\nu4\n".utf8), label: "Order.java"),
      a: SourceFile(bytes: Data("u0\nu2\nA3\nu4\n".utf8), label: "Order.java"),
      b: SourceFile(bytes: Data("u0\nB1\nu2\nB3\nu4\n".utf8), label: "Order.java"),
      options: ComparisonOptions(mode: .windowDefault))
    let controller = try Windows.controller(for: session)
    let headers = controller.presentation.headers
    #expect([Role.base, .a, .b].map { headers[$0]?.distinctName } == ["Base", "A", "B"])
    // The header still shows the file's name beside the letter.
    #expect(headers[.a]?.name == "Order.java")
    let conflict = try #require(controller.presentation.navigation.firstOpenConflict)
    #expect(try Self.preview(ofBlock: conflict, in: controller).contains("A removed these lines"))
    // The help tags of the toggles and the context menu above use the letters too.
    let toggles = try #require(controller.presentation.mergeDecisionColumn.decisions[conflict])
      .toggles
    #expect(toggles.map(\.help).contains("Remove these lines, as A did."))
    #expect(toggles.map(\.help).contains("Take the version of B."))
    controller.presentation.setCurrentBlock(conflict)
    let b = try #require(controller.layout.sourcePane(.b))
    let hit = PaneHit(row: b.content.blocks[conflict].rows.lowerBound, block: conflict)
    let titles = controller.contextMenu(for: hit, in: b).items.map(\.title)
    #expect(titles.contains("Use Version of B"))
  }

  /// The text of the result in the rows of `block`.
  private static func preview(ofBlock block: Int, in controller: SessionWindowController) throws
    -> String
  {
    let result = try controller.mergeResult
    return result.content.text(ofLinesIn: result.content.blocks[block].rows)
  }
}
