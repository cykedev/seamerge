import AppKit
import MergeModel
import PaneKit
import Testing
import TextBasics

@testable import SeamergeUI

/// What each pane shows of a merge: blocks, tints, markers, previews, decisions and marks.
@MainActor
@Suite struct PresentationTests {
  @Test func sidesAreTintedWhereTheyChangedAndTheBaseRedWhereAConflictIsOpen() async throws {
    let controller = try await helloWorldWindow()
    let styles = controller.layout.sourcePanes.map { $0.pane.content.blocks.map(\.style) }
    #expect(styles[0] == [.tinted(.a), .tinted(.a), .tinted(.a)])
    #expect(styles[1] == [.original, .tinted(.conflict), .original])
    #expect(styles[2] == [.unchanged, .tinted(.b), .unchanged])
  }

  @Test func markersSayHowEachSideChangedAndTheConflictMarkStandsOnTheBase() async throws {
    let controller = try await helloWorldWindow()
    let blocks = controller.layout.sourcePanes.map(\.pane.content.blocks)
    #expect(blocks[0].map(\.marker) == [.changed, .changed, .changed])
    #expect(blocks[1].map(\.marker) == [nil, nil, nil])
    #expect(blocks[2].map(\.marker) == [nil, .changed, nil])
    #expect(
      blocks.map { $0.map(\.conflict) } == [
        [nil, nil, nil], [nil, .open, nil], [nil, nil, nil],
      ])
  }

  @Test func everyPaneHasTheChangedBlocksAndTheSidesShareTheirRows() async throws {
    let controller = try await helloWorldWindow()
    let rows = controller.layout.sourcePanes.map { $0.pane.content.blocks.map(\.rows) }
    #expect(rows[0] == rows[1] && rows[1] == rows[2])
    #expect(try controller.mergeResult.content.blocks.count == rows[0].count)
  }

  @Test func resultShowsTheOpenConflictAsPreviewsOfAThenB() async throws {
    let controller = try await helloWorldWindow()
    let content = try controller.mergeResult.content
    let text = content.text as NSString
    #expect(content.previews.map(\.role) == [.a, .b])
    #expect(
      content.previews.map { text.substring(with: NSRange($0.range)) } == [
        "    // single-line comment\n    public satic void main(String[] args)\n",
        "    // This is a single-line comment\n    public static void main(String args[])\n",
      ])
    #expect(content.blocks.map(\.style) == [.tinted(.a), .tinted(.conflict), .tinted(.a)])
  }

  @Test func decisionColumnShowsTheSourceTakenAndTheOpenConflict() async throws {
    let controller = try await helloWorldWindow()
    let decisions = try controller.presentation.mergeDecisionColumn.decisions
    #expect(decisions[0]?.state == .automatic([.a]))
    #expect(decisions[1]?.state == .open)
    #expect(decisions[2]?.state == .automatic([.a]))
    #expect(decisions[1]?.toggles.allSatisfy { !$0.isOn } == true)
    #expect(
      decisions[0]?.toggles.map(\.help) == [
        "Take the version of HelloWorld2.java.", "Take the version of HelloWorld1.java.",
      ])
  }

  @Test func overviewMarksPutATheLeadingSideBTheTrailingAndConflictsFullWidth() async throws {
    let controller = try await helloWorldWindow()
    let sources = controller.presentation.sourcesOverviewBar.marks
    #expect(sources.map(\.placement) == [.leading, .fullWidth, .leading])
    #expect(sources.map(\.style) == [.tinted(.a), .tinted(.conflict), .tinted(.a)])
    #expect(
      sources.map(\.accessibilityLabel) == [
        "Change in A, line 1", "Open conflict, line 4", "Change in A, line 9",
      ])
    let result = try controller.presentation.mergeResultOverviewBar.marks
    #expect(result.map(\.placement) == [.leading, .fullWidth, .leading])
    #expect(
      result.map(\.accessibilityLabel) == [
        "From A, line 1", "Open conflict, line 6", "From A, line 11",
      ])
    #expect(
      controller.layout.sourcePane(.b)?.overviewBar === controller.presentation.sourcesOverviewBar)
    let resultOverviewBar = try controller.presentation.mergeResultOverviewBar
    #expect(try controller.mergeResult.overviewBar === resultOverviewBar)
  }

  @Test func changeBothSidesMadeIsMarkedOnBothSidesOfTheBarAndMixedInTheResult() async throws {
    let session = try await SampleMerges.TouchingBlocks.changeThenBoth.session()
    let controller = makeController(session)
    let marks = controller.presentation.sourcesOverviewBar.marks
    #expect(marks.map(\.placement) == [.leading, .leading, .trailing])
    #expect(marks.map(\.block) == [0, 1, 1])
    #expect(try controller.mergeResult.content.blocks.map(\.style) == [.tinted(.a), .combined])
  }

  @Test func mergeWithoutABaseHasNoBasePaneAndMarksConflictsOnB() async throws {
    let session = try await SampleMerges.merge(
      base: nil, a: "same\nfrom a\nsame again\n", b: "same\nfrom b\nsame again\n")
    let controller = makeController(session)
    #expect(controller.layout.sourcePanes.map(\.role) == [.a, .b])
    let b = try #require(controller.layout.sourcePane(.b))
    #expect(b.content.blocks.map(\.conflict) == [.open])
    #expect(b.content.blocks.map(\.marker) == [.changed])
  }

  @Test func linesOfACRLFFileEndInCRLF() async throws {
    let scenario = try #require(Scenario.merges.first { $0.name == "crlf" })
    let (session, context) = try await scenario.load()
    let controller = makeController(session, context: context)
    for (_, pane) in controller.layout.sourcePanes {
      let content = pane.content
      let endings = zip(content.lineNumbers, content.lineEndings).filter { $0.0 >= 0 }.map(\.1)
      #expect(Set(endings) == [.crlf])
    }
    let result = try controller.mergeResult.content
    #expect(Set(result.lineEndings) == [.crlf])
    #expect(!result.text.contains("\r"))
  }

  @Test func linesOfAFileEndAsTheFileEndsThem() {
    let mixed = SourceFile(bytes: Data("one\r\ntwö\nthree\r\nlast".utf8), label: "mixed")
    #expect(
      PaneContent.lineEndings(of: mixed, lineCount: 4) == [
        .crlf, .lf, .crlf, nil,
      ])
    let classic = SourceFile(bytes: Data("one\rtwo\r".utf8), label: "classic")
    #expect(
      PaneContent.lineEndings(of: classic, lineCount: 2) == [.cr, .cr])
    #expect(
      PaneContent.lineEndings(of: classic, lineCount: 3)
        == Array(repeating: .cr, count: 3))
    let empty = SourceFile(bytes: Data(), label: "empty")
    #expect(PaneContent.lineEndings(of: empty, lineCount: 0) == [])
  }

  @Test func resultRowsBreakWhereTheTextSystemBreaksLines() {
    let rows = ResultPaneContent.rows(of: "one\r\ntwo\rthree\nfour\u{2028}five")
    #expect(rows.text == "one\ntwo\nthree\nfour\nfive")
    #expect(
      rows.lineEndings == [
        .crlf, .cr, .lf, .lf, nil,
      ])
    #expect(rows.starts == LineStarts([0, 4, 8, 14, 19, 24]))
    #expect(rows.rows(ofUTF16: 0..<5) == 0..<1)
    #expect(rows.rows(ofUTF16: 5..<10) == 1..<3)
    #expect(rows.rows(ofUTF16: 10..<10) == 2..<2)
    #expect(rows.rows(ofUTF16: 24..<24) == 4..<4)
    #expect(rows.rows(ofUTF16: 20..<24) == 4..<5)
  }

  @Test func resultEndingWithALineBreakHasNoEmptyRowAfterIt() async throws {
    let rows = ResultPaneContent.rows(of: "one\r\ntwo\n")
    #expect(rows.text == "one\ntwo")
    #expect(rows.lineEndings == [.crlf, .lf])
    #expect(rows.rows(ofUTF16: 9..<9) == 2..<2)
    #expect(ResultPaneContent.rows(of: "\n").lineEndings == [.lf])
    #expect(ResultPaneContent.rows(of: "").lineEndings == [nil])

    // Like the panes of the inputs: B has 9 lines, the result 15, each with its number.
    let controller = try await helloWorldWindow()
    #expect(controller.layout.sourcePane(.b)?.content.lineNumbers.filter { $0 >= 0 }.count == 9)
    #expect(try controller.mergeResult.content.lineNumbers == (0..<15).map(Int32.init))
  }

  /// The rows of the result pane and the scroll map split the result text into lines each on
  /// their own; they must agree on where every block starts and how many lines there are, also
  /// at CR, CRLF, NEL, U+2028 and a block that starts within a line.
  @Test func resultRowsAgreeWithTheScrollMapAtEveryKindOfLineBreak() async throws {
    let session = try await SampleMerges.merge(
      base: "u\r\nx\r\nv\r\nw\r\ny\r\nz\r\n",
      a: "u\r\na\u{2028}b\r\nv\r\nw\r\ny\r\nz from a\r\n",
      b: "u\r\nx\r\nv\rq\u{85}r\r\nw\r\ny\r\nz from b\r\n")
    var document = ResultDocument(session: session)
    var text = document.initialText
    try check(document, text: text)

    // Removing the line break at the end of the first block makes the second start within a
    // line.
    let firstEnd = document.range(of: session.blocks[0]).upperBound
    let plan = document.plan(for: TextReplacement(range: firstEnd - 2..<firstEnd, text: ""))
    var replaced: [String] = []
    for replacement in plan.replacements {
      let nsText = NSMutableString(string: text)
      replaced.append(nsText.substring(with: NSRange(replacement.range)))
      nsText.replaceCharacters(in: NSRange(replacement.range), with: replacement.text)
      text = nsText as String
    }
    document.apply(plan, replacedTexts: replaced)
    #expect(!text.hasPrefix("u\r\n"))
    try check(document, text: text)

    func check(_ document: ResultDocument, text: String) throws {
      let changes = SessionChanges(session: session)
      let content = ResultPaneContent(
        result: ResultState(document: document, text: text), changes: changes, headers: [:]
      ).content
      let map = ScrollMap(document: document, text: text)
      let layout = session.rowLayout
      for (block, paneBlock) in zip(changes.blocks, content.blocks) {
        let line = map.targetPosition(at: Double(layout.rows(of: block).lowerBound))
        #expect(Double(paneBlock.rows.lowerBound) == line, "block \(block.id)")
      }
      let endedLines = content.lineEndings.count { $0 != nil }
      #expect(map.targetPosition(at: Double(layout.rowCount)) == Double(endedLines))
    }
  }

  @Test func longUnchangedRunsCollapseInEveryPaneAndExpandTogether() async throws {
    let scenario = try #require(Scenario.merges.first { $0.name == "big" })
    let (session, context) = try await scenario.load()
    let controller = makeController(session, context: context)
    let panes = controller.layout.sourcePanes.map(\.pane)
    let runs = panes[0].collapsedRuns
    #expect(runs.count == 40)
    #expect(panes.allSatisfy { $0.collapsedRuns == runs })
    #expect(try controller.mergeResult.collapsedRuns.count == runs.count)

    controller.presentation.pane(panes[1], didAskToExpand: runs[3])
    #expect(panes.allSatisfy { $0.collapsedRuns.count == runs.count - 1 })
    #expect(!panes[0].collapsedRuns.contains(runs[3]))
    #expect(try controller.mergeResult.collapsedRuns.count == runs.count - 1)

    let resultRun = try #require(controller.mergeResult.collapsedRuns.last)
    try controller.presentation.pane(controller.mergeResult, didAskToExpand: resultRun)
    #expect(panes.allSatisfy { $0.collapsedRuns.count == runs.count - 2 })
    #expect(!panes[0].collapsedRuns.contains(runs[runs.count - 1]))
  }

  private func helloWorldWindow() async throws -> SessionWindowController {
    makeController(try await SampleMerges.helloWorld())
  }

  private func makeController(
    _ session: Session, context: SessionContext = SessionContext()
  ) -> SessionWindowController {
    SessionWindowController(
      session: session, context: context, undoManager: UndoManager(),
      displayOptions: DisplayOptions(), pasteboard: .withUniqueName(),
      workspace: WorkspaceRecorder(),
      prompts: PromptRecorder(), doneStyle: .standard, settings: .private(),
      window: SessionWindow())
  }
}
