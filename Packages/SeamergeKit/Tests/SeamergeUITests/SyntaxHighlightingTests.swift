import AppKit
import MergeModel
import PaneKit
import SyntaxKit
import Testing
import TextBasics

@testable import SeamergeUI

/// Coloring the code by its syntax: the window shows its lines before they are lexed, every pane
/// gets the tokens of its file in the background, and the tokens of the result follow typing and
/// commands as a full lex of its text would have them.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct SyntaxHighlightingTests {
  @Test func windowShowsItsLinesBeforeTheyAreLexed() async throws {
    let controller = try Windows.controller(for: try await SyntaxFixture.merge())

    for pane in Windows.panes(of: controller) {
      #expect(!pane.content.text.isEmpty)
      #expect(pane.syntaxProvider == nil)
    }
  }

  @Test func everyPaneGetsTheTokensOfItsFileInTheBackground() async throws {
    let controller = try Windows.controller(for: try await SyntaxFixture.merge())
    await SyntaxFixture.lexing(of: controller)

    for (role, pane) in controller.layout.sourcePanes {
      let text = try #require(controller.presentation.changes.session.file(for: role)?.text)
      try SyntaxFixture.expectTokens(of: pane, asInLexOf: text, "\(role)")
    }
    let result = try controller.mergeResult
    try SyntaxFixture.expectTokens(of: result, asInLexOf: result.content.text, "result")
    let keyword = try #require(result.syntaxProvider).tokens(inLine: 0).first
    #expect(keyword == PaneToken(range: 0..<6, kind: .keyword))
  }

  @Test(arguments: Input.allCases)
  func typingInTheResultLexesItAgainAtOnce(input: Input) async throws {
    let controller = try Windows.controller(for: try await SyntaxFixture.merge())
    await SyntaxFixture.lexing(of: controller)
    let result = try controller.mergeResult
    let tokens = try #require(result.syntaxProvider)

    // An opening block comment at the start of the second line reaches to the end of the text.
    try controller.type("/*", over: 18..<18, with: input)
    #expect(result.syntaxProvider === tokens)
    try SyntaxFixture.expectTokens(of: result, asInLexOf: result.content.text, "after /*")

    try controller.type("*/\n", over: 21..<21, with: input)
    #expect(result.syntaxProvider === tokens)
    try SyntaxFixture.expectTokens(of: result, asInLexOf: result.content.text, "after */")
  }

  @Test func commandsAndUndoKeepTheTokensOfTheResult() async throws {
    let undoManager = UndoManager()
    let controller = try Windows.controller(
      for: try await SyntaxFixture.merge(), undoManager: undoManager)
    await SyntaxFixture.lexing(of: controller)
    let result = try controller.mergeResult
    let tokens = try #require(result.syntaxProvider)

    controller.resolveAllWithA(nil)
    #expect(result.syntaxProvider === tokens)
    try SyntaxFixture.expectTokens(of: result, asInLexOf: result.content.text, "resolved")

    undoManager.undo()
    #expect(result.syntaxProvider === tokens)
    try SyntaxFixture.expectTokens(of: result, asInLexOf: result.content.text, "undone")
  }

  @Test func rowsOfSeveralEditsAreThoseOfTheTextTheyLeave() throws {
    let seed: UInt64 = 1913
    var generator = SeededGenerator(seed: seed)
    let pieces = ["", "x", "\n", "ab\n", "\n\n", "cd"]
    for round in 0..<300 {
      var text = (0..<6).map { _ in pieces.randomElement(using: &generator) ?? "" }.joined()
      let before = ResultPaneContent.rows(of: text + "\n").starts
      var edits: [PaneEdit] = []
      for _ in 0..<Int.random(in: 1...4, using: &generator) {
        let length = text.utf16.count
        let lower = Int.random(in: 0...length, using: &generator)
        let upper = Int.random(in: lower...min(length, lower + 4), using: &generator)
        let inserted = pieces.randomElement(using: &generator) ?? ""
        edits.append(PaneEdit(range: lower..<upper, text: inserted))
        text.replaceUTF16Range(lower..<upper, with: inserted)
      }
      let change = try #require(SessionSyntax.rowChange(of: edits, from: before))
      let after = ResultPaneContent.rows(of: text + "\n").starts
      #expect(change.starts == after, "seed \(seed), round \(round)")
      #expect(
        before.lineCount - change.oldRows.count + change.newRowCount == after.lineCount,
        "seed \(seed), round \(round)")
    }
  }

  @Test func fileOfAnUnknownLanguageHasNoTokens() async throws {
    let controller = try Windows.controller(
      for: try await SyntaxFixture.merge(named: "notes.unknown"))
    await SyntaxFixture.lexing(of: controller)

    for pane in Windows.panes(of: controller) {
      let provider = try #require(pane.syntaxProvider)
      for line in 0..<pane.content.lineNumbers.count {
        #expect(provider.tokens(inLine: line).isEmpty)
      }
    }
  }

  @Test func languageComesFromTheResultThenTheNewerFileThenItsFirstLine() async throws {
    let session = try await SyntaxFixture.merge(named: "Sample")
    #expect(SessionSyntax.language(of: session, resultURL: nil) == .plainText)
    #expect(
      SessionSyntax.language(of: session, resultURL: URL(filePath: "/tmp/merged.py")).name
        == "Python")
    let script = try await SyntaxFixture.merge(named: "build", firstLine: "#!/bin/zsh")
    #expect(SessionSyntax.language(of: script, resultURL: nil).name == "Shell")
    let swift = try await SyntaxFixture.merge()
    #expect(SessionSyntax.language(of: swift, resultURL: nil).name == "Swift")
    // A first line of two megabytes still names its interpreter at its start.
    let long = try await SyntaxFixture.merge(
      named: "run", firstLine: "#!/usr/bin/env python3 " + String(repeating: "x", count: 2_000_000))
    #expect(SessionSyntax.language(of: long, resultURL: nil).name == "Python")
  }
}

/// A merge of Swift code, and how the tests wait for and check its tokens.
@MainActor
enum SyntaxFixture {
  /// A merge of four lines of Swift, in files named `name`, in which A and B change the second
  /// line differently; the second line starts at offset 18 in every pane.
  static func merge(named name: String = "Sample.swift", firstLine: String = "import Foundation")
    async throws -> Session
  {
    let base = "\(firstLine)\nlet a = 1\nlet b = \"two\" // end\n"
    let a = "\(firstLine)\nlet a = 10\nlet b = \"two\" // end\n"
    let b = "\(firstLine)\nvar a = 1\nlet b = \"two\" // end\n"
    return try await Session.merge(
      base: SourceFile(bytes: Data(base.utf8), label: name),
      a: SourceFile(bytes: Data(a.utf8), label: name),
      b: SourceFile(bytes: Data(b.utf8), label: name),
      options: ComparisonOptions(mode: .windowDefault))
  }

  /// Returns once every pane of the window has its tokens.
  static func lexing(of controller: SessionWindowController) async {
    while Windows.panes(of: controller).contains(where: { $0.syntaxProvider == nil }) {
      await Task.yield()
    }
  }

  /// Records an issue for each row of `pane` whose tokens differ from those of its line in a
  /// full lex of `text`.
  static func expectTokens(
    of pane: PaneView, asInLexOf text: String, _ comment: Comment,
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let provider = try #require(pane.syntaxProvider)
    let lexed = LexedText(
      language: LanguageDescription(fileName: "Sample.swift"),
      lines: text.split(separator: "\n", omittingEmptySubsequences: false))
    for line in pane.content.lineNumbers where line >= 0 {
      let expected = lexed.tokens(inLine: Int(line)).map {
        PaneToken(range: $0.range, kind: PaneToken.Kind($0.kind))
      }
      #expect(
        provider.tokens(inLine: Int(line)) == expected, "\(comment), line \(line)",
        sourceLocation: sourceLocation)
    }
  }
}
