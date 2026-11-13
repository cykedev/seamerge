import AppKit
import MergeModel
import PaneKit
import SyntaxKit
import Testing

@testable import SeamergeUI

/// Coloring the code by its syntax: the window shows its lines before they are lexed, and every
/// pane above the result gets the tokens of its file in the background.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct SyntaxHighlightingTests {
  @Test func windowShowsItsLinesBeforeTheyAreLexed() async throws {
    let controller = try Windows.controller(for: try await SyntaxFixture.merge())

    for (_, pane) in controller.layout.sourcePanes {
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
    let base = try #require(controller.layout.sourcePane(.base))
    let keyword = try #require(base.syntaxProvider).tokens(inLine: 0).first
    #expect(keyword == PaneToken(range: 0..<6, kind: .keyword))
  }

  @Test func fileOfAnUnknownLanguageHasNoTokens() async throws {
    let controller = try Windows.controller(
      for: try await SyntaxFixture.merge(named: "notes.unknown"))
    await SyntaxFixture.lexing(of: controller)

    for (_, pane) in controller.layout.sourcePanes {
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

  /// Returns once every pane above the result has its tokens.
  static func lexing(of controller: SessionWindowController) async {
    while controller.layout.sourcePanes.contains(where: { $0.pane.syntaxProvider == nil }) {
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
