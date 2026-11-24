import AppKit
import FolderCompare
import GitSupport
import MergeModel
import Testing

@testable import SeamergeUI

/// The subtitle of a comparison: the changes by kind, read from left to right, with only the
/// kinds there are; which file of a run it shows only when the run has more than one; and the
/// changes as the last part to stay when the window narrows.
@MainActor
@Suite struct DiffSubtitleTests {
  @Test func comparisonOfOneFileSummarizesItsChangesByKind() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())
    let window = try #require(controller.window)
    #expect(window.subtitle == "1 addition · 1 change · 1 deletion")
    #expect(
      window.accessibilityTitle()
        == "Greeting.swift, 1 addition · 1 change · 1 deletion")
  }

  @Test func comparisonOfTwelveFilesNamesTheFileAfterItsChanges() async throws {
    let controller = try Windows.controller(
      for: try await SampleDiffs.greeting(), context: SampleDiffs.gitContext)
    #expect(controller.window?.subtitle == "1 addition · 1 change · 1 deletion · File 3 of 12")
  }

  @Test func runOfOneFileHasNoFileToCount() async throws {
    let context = SessionContext(
      difftool: DifftoolContext(
        path: "Sources/Greeting.swift", leftRole: .before, rightRole: .workingCopy,
        filePosition: FilePosition(number: 1, count: 1)))
    let controller = try Windows.controller(
      for: try await SampleDiffs.greeting(), context: context)
    #expect(controller.window?.subtitle == "1 addition · 1 change · 1 deletion")
  }

  @Test func onlyTheKindsThereAreAreNamedInTheSingularOrThePlural() async throws {
    let cases: [(edits: [Edit], subtitle: String)] = [
      ([.insert(at: 4)], "1 addition"),
      ([.insert(at: 4), .insert(at: 30)], "2 additions"),
      ([.delete(at: 4)], "1 deletion"),
      ([.delete(at: 4), .delete(at: 30)], "2 deletions"),
      ([.change(at: 4)], "1 change"),
      ([.change(at: 4), .change(at: 18), .change(at: 30)], "3 changes"),
      ([.delete(at: 4), .insert(at: 18), .change(at: 30)], "1 addition · 1 change · 1 deletion"),
      (
        [.insert(at: 2), .insert(at: 10), .change(at: 18), .insert(at: 26), .delete(at: 34)],
        "3 additions · 1 change · 1 deletion"
      ),
    ]
    for (edits, subtitle) in cases {
      let session = try await Self.comparison(with: edits)
      #expect(Self.summary(of: session).changes == subtitle, "\(edits)")
    }
  }

  @Test func equalFilesHaveNoChanges() async throws {
    let session = try await Self.comparison(with: [])
    let controller = try Windows.controller(for: session)
    #expect(controller.window?.subtitle == "No changes")
  }

  @Test func swappedSidesReadTheChangesTheOtherWay() async throws {
    let controller = try Windows.controller(
      for: try await Self.comparison(with: [.insert(at: 4), .insert(at: 30)]))
    controller.swapSides(nil)
    #expect(controller.window?.subtitle == "2 deletions")
    controller.swapSides(nil)
    #expect(controller.window?.subtitle == "2 additions")
  }

  @Test func changesStandBeforeTheComparisonMode() async throws {
    let session = try await SampleDiffs.diff(
      old: SampleDiffs.greetingOld, new: SampleDiffs.greetingNew, mode: .exact)
    let summary = Self.summary(of: session)
    #expect(summary.changes == "1 addition · 1 change · 1 deletion · Compared exactly")
  }

  @Test func whileTheFilesAreComparedTheChangesAreNotCountedYet() async throws {
    let session = try await SampleDiffs.greeting()
    let summary = SessionSummary(
      changes: SessionChanges(session: session, origin: .a), context: SessionContext(),
      arrangement: PaneArrangement(session: session), startMode: .windowDefault,
      ignoredDifferences: nil, isComparing: true)
    #expect(summary.changes == "")
  }

  @Test func narrowWindowDropsTheFoldersThenTheFileAndKeepsTheChanges() async throws {
    let session = try await SampleDiffs.greeting()
    var context = SampleDiffs.gitContext
    context.folders = FolderPair(
      left: URL(filePath: "/Projects/Orders 1.0"), right: URL(filePath: "/Projects/Orders 1.1"))
    let summary = Self.summary(of: session, context: context)
    let font = NSFont.preferredFont(forTextStyle: .subheadline)
    let changes = "1 addition · 1 change · 1 deletion"
    let widths = [
      changes + " · File 3 of 12 · Orders 1.0 ↔ Orders 1.1", changes + " · File 3 of 12",
      changes,
    ].map { ($0 as NSString).size(withAttributes: [.font: font]).width }
    #expect(summary.fullSubtitle == changes + " · File 3 of 12 · Orders 1.0 ↔ Orders 1.1")
    #expect(summary.subtitle(fittingWidth: widths[0], font: font) == summary.fullSubtitle)
    #expect(
      summary.subtitle(fittingWidth: widths[0] - 1, font: font) == changes + " · File 3 of 12")
    #expect(summary.subtitle(fittingWidth: widths[1] - 1, font: font) == changes)
    #expect(summary.subtitle(fittingWidth: widths[2] - 1, font: font) == changes)
  }

  @Test func narrowWindowShowsTheChangesInItsSubtitle() async throws {
    let controller = try Windows.controller(
      for: try await SampleDiffs.greeting(), context: SampleDiffs.gitContext)
    let window = try #require(controller.window)
    defer { window.close() }
    Rendering.prepare(window, size: window.contentMinSize, appearance: Look.light.appearance)
    controller.stateDidChange()
    #expect(window.subtitle.hasPrefix("1 addition · 1 change · 1 deletion"))
  }

  /// The summary of `session` as a new window of a comparison has it, in `context`.
  private static func summary(
    of session: Session, context: SessionContext = SessionContext()
  ) -> SessionSummary {
    let arrangement = PaneArrangement(session: session)
    return SessionSummary(
      changes: SessionChanges(session: session, origin: arrangement.origin), context: context,
      arrangement: arrangement, startMode: .windowDefault, ignoredDifferences: nil)
  }

  /// A comparison of forty lines with `edits` made to the newer side; each edit is at a line of
  /// the older side, far enough from the others to stand as a block of its own.
  private static func comparison(with edits: [Edit]) async throws -> Session {
    let old = (0..<40).map { "let value\($0) = \($0)" }
    var new = old
    for edit in edits.sorted(by: { $0.line > $1.line }) {
      switch edit {
      case .insert(let line): new.insert("let added\(line) = 0", at: line)
      case .delete(let line): new.remove(at: line)
      case .change(let line): new[line] += " * 2"
      }
    }
    func text(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }
    return try await SampleDiffs.diff(old: text(old), new: text(new), label: "Values.swift")
  }

  /// An edit of one line of the newer side of a comparison.
  enum Edit: CustomStringConvertible {
    case insert(at: Int)
    case delete(at: Int)
    case change(at: Int)

    var line: Int {
      switch self {
      case .insert(let line), .delete(let line), .change(let line): line
      }
    }

    var description: String {
      switch self {
      case .insert(let line): "insert at \(line)"
      case .delete(let line): "delete at \(line)"
      case .change(let line): "change at \(line)"
      }
    }
  }
}
