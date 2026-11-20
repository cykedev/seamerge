import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The search of a session window while the window gives its panes new text or new sections:
/// during and right after a switch of the comparison mode, of the arrangement, of the base, of
/// the collapsed lines, a reload of a changed file and a switch of the ignore rules, each time
/// also while the search for a text with many matches still runs.
///
/// After every switch the window shows the matches of the text as it is now, as many as the
/// panes it searches hold and each where the text is.
///
/// The finder keeps its search text on the find pasteboard of the system, which every app
/// shares; each test puts back what it held, whether the test passes or not.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SearchDuringSwitchTests {
  /// The number of lines of each file.
  static let lineCount = 3_000

  /// The text that every line holds, which the finder takes a while to find all of.
  static let common = "compute"

  /// Line `index` of the older file or of the newer one.
  ///
  /// The newer file has a later timestamp on every line, which the rule for timestamps ignores;
  /// every fortieth line changed for real and every thirtieth in its whitespace alone.
  static func line(_ index: Int, newer: Bool) -> String {
    let second = String(format: "%02d", index % 60)
    let stamp = newer ? "2026-11-15 13:40:\(second)" : "2026-11-14 09:12:\(second)"
    var call = "compute(entry-\(index);)"
    if newer, index % 40 == 20 {
      call = call.replacingOccurrences(of: "compute(", with: "measure(")
    }
    let space = newer && index % 30 == 15 ? "  " : " "
    return stamp + space + call
  }

  /// The older or the newer file.
  static func file(newer: Bool) -> String {
    (0..<lineCount).map { line($0, newer: newer) }.joined(separator: "\n") + "\n"
  }

  /// A text that a single unchanged line holds, in each file.
  static func rare(_ index: Int) -> String {
    precondition(index % 40 != 20, "Line \(index) changed")
    return "entry-\(index);"
  }

  /// The comparison of the two files.
  private static func diff(settings: UserSettings = .private()) async throws -> Session {
    try await Session.diff(
      old: SourceFile(bytes: Data(file(newer: false).utf8), label: "old.log"),
      new: SourceFile(bytes: Data(file(newer: true).utf8), label: "new.log"),
      mode: .windowDefault, ignoring: settings.ignoreRules)
  }

  /// Searches for `needle` at once and waits until the window shows its matches: as many as the
  /// panes searched hold, each where the needle is.
  private func expectMatches(of needle: String, with driver: SearchDriver) async throws {
    try driver.type(needle)
    let presentation = driver.controller.presentation
    let expected = {
      presentation.searchedPanes.reduce(0) {
        $0 + $1.documentView.string.components(separatedBy: needle).count - 1
      }
    }
    let holdNeedle = {
      driver.search.matches.allSatisfy {
        ($0.pane.documentView.string as NSString).substring(with: NSRange($0.range)) == needle
      }
    }
    await driver.waitForMatches {
      driver.search.matchesAreCurrent && driver.search.matches.count == expected() && holdNeedle()
    }
    #expect(driver.search.matches.count == expected(), "\(needle)")
    #expect(driver.search.matches.count > 0, "\(needle)")
    #expect(holdNeedle(), "\(needle)")
  }

  /// Opens the find bar of `controller` and starts the search for the common text, without
  /// waiting for its matches.
  private func startSearch(in controller: SessionWindowController) throws -> SearchDriver {
    let driver = SearchDriver(controller)
    #expect(try driver.send(.find))
    try driver.type(Self.common)
    return driver
  }

  @Test func comparisonModeSwitchesWhileTheSearchRuns() async throws {
    try await FindPasteboard.preserving {
      let controller = try Windows.controller(for: try await Self.diff())
      defer { controller.window?.close() }
      let driver = try startSearch(in: controller)
      for (index, mode) in [ComparisonMode.exact, .ignoreAllWhitespace, .ignoreWhitespaceAmount]
        .enumerated()
      {
        try driver.type(Self.common)
        var options = controller.comparisonOptions
        options.mode = mode
        let switching = Task { [options] in await controller.switchComparison(to: options) }
        // While the engine compares, the window still shows the old comparison.
        try driver.type(Self.rare(101 + index))
        await switching.value
        #expect(controller.presentation.changes.session.options.mode == mode)
        try await expectMatches(of: Self.rare(201 + index), with: driver)
      }
    }
  }

  @Test func arrangementSwitchesWhileTheSearchRuns() async throws {
    try await FindPasteboard.preserving {
      let controller = try Windows.controller(for: try await Self.diff())
      defer { controller.window?.close() }
      let driver = try startSearch(in: controller)
      for (index, command) in [
        SessionCommand.showConnectedSides, .showSingleColumn,
        .showAlignedLines, .showSingleColumn, .showConnectedSides,
      ].enumerated() {
        try driver.type(Self.common)
        controller.perform(command)
        try await expectMatches(of: Self.rare(301 + index), with: driver)
      }
    }
  }

  @Test func baseHidesAndShowsWhileTheSearchRuns() async throws {
    try await FindPasteboard.preserving {
      // Changes on both sides, none of them a conflict, so that the result holds no preview.
      let base = Self.file(newer: false)
      let session = try await SampleMerges.merge(
        base: base, a: base.replacingOccurrences(of: "entry-7;", with: "entry-7a;"),
        b: base.replacingOccurrences(of: "entry-3007;", with: "entry-3007b;"))
      let controller = try Windows.controller(for: session)
      defer { controller.window?.close() }
      let driver = try startSearch(in: controller)
      for index in 0..<4 {
        try driver.type(Self.common)
        controller.perform(.toggleBase)
        #expect(controller.layout.showsBase == (index % 2 == 1))
        try await expectMatches(of: Self.rare(401 + index), with: driver)
      }
    }
  }

  @Test func allLinesShowAndCollapseWhileTheSearchRuns() async throws {
    try await FindPasteboard.preserving {
      let settings = UserSettings.private()
      settings.enabledBuiltInIgnoreRules = [.timestamps]
      let controller = try Windows.controller(
        for: try await Self.diff(settings: settings), settings: settings)
      defer { controller.window?.close() }
      let driver = try startSearch(in: controller)
      for (index, command) in [SessionCommand.showAllLines, .collapseUnchangedLines, .showAllLines]
        .enumerated()
      {
        try driver.type(Self.common)
        controller.perform(command)
        try await expectMatches(of: Self.rare(501 + index), with: driver)
      }
    }
  }

  @Test func ignoreRulesSwitchOffAndOnWhileTheSearchRuns() async throws {
    try await FindPasteboard.preserving {
      let settings = UserSettings.private()
      settings.enabledBuiltInIgnoreRules = [.timestamps]
      let controller = try Windows.controller(
        for: try await Self.diff(settings: settings), settings: settings)
      defer { controller.window?.close() }
      let driver = try startSearch(in: controller)
      for index in 0..<2 {
        try driver.type(Self.common)
        let uses = !controller.usesIgnoreRules
        let switching = Task { await controller.compareWithRequestedRules(usingIgnoreRules: uses) }
        try driver.type(Self.rare(601 + index))
        await switching.value
        #expect(controller.usesIgnoreRules == uses)
        try await expectMatches(of: Self.rare(701 + index), with: driver)
      }
    }
  }

  /// A comparison of the two files read from `folder`, whose newer file the test may change.
  private static func diffOfFiles(in folder: URL) async throws -> (session: Session, new: URL) {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let old = folder.appending(path: "old.log")
    let new = folder.appending(path: "new.log")
    try Data(file(newer: false).utf8).write(to: old)
    try Data(file(newer: true).utf8).write(to: new)
    let session = try await Session.loadDiff(
      old: SessionFile(url: old, label: "old.log"), new: SessionFile(url: new, label: "new.log"),
      mode: .windowDefault)
    return (session, new)
  }

  /// A folder of its own for the files of a test.
  private static func newFolder() -> URL {
    FileManager.default.temporaryDirectory.appending(
      path: "SearchDuringSwitchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  }

  /// The newer file with its first `lineCount` lines only.
  private static func newerFile(prefix lineCount: Int) -> String {
    file(newer: true).components(separatedBy: "\n").prefix(lineCount).joined(separator: "\n")
      + "\n"
  }

  @Test func fileChangedOnDiskReloadsWhileTheSearchRuns() async throws {
    try await FindPasteboard.preserving {
      let folder = Self.newFolder()
      defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
      let (session, new) = try await Self.diffOfFiles(in: folder)
      let controller = try Windows.controller(for: session)
      defer { controller.window?.close() }
      let driver = try startSearch(in: controller)
      // Fewer lines, so that the search text gets shorter, then the lines again.
      let texts = [Self.newerFile(prefix: Self.lineCount / 2), Self.file(newer: true)]
      for (index, text) in texts.enumerated() {
        try Data(text.utf8).write(to: new)
        try driver.type(Self.common)
        let reloading = Task { await controller.diskWatch.reloadChangedFiles() }
        try driver.type(Self.rare(801 + index))
        await reloading.value
        #expect(controller.presentation.changes.session.inputs.b.text == text)
        try await expectMatches(of: Self.rare(901 + index), with: driver)
      }
    }
  }

  /// The seed of the random sequence of searches, switches, undo and reloads, which every
  /// failure names, so that the sequence can be repeated.
  static let seed: UInt64 = 0x5EA2_C44D

  /// A random line that holds a rare text in both files, as one search after another needs.
  private static func randomUnchangedLine(using generator: inout SeededGenerator) -> Int {
    let line = Int.random(in: 0..<lineCount / 2, using: &generator)
    return line % 40 == 20 ? line + 1 : line
  }

  @Test func randomSearchesWhileTheWindowSwitchesUndoesAndReloadsEndWithTheirMatches()
    async throws
  {
    try await FindPasteboard.preserving {
      let folder = Self.newFolder()
      defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
      let (session, new) = try await Self.diffOfFiles(in: folder)
      let controller = try Windows.controller(for: session)
      defer { controller.window?.close() }
      let undoManager = controller.sessionUndoManager
      var generator = SeededGenerator(seed: Self.seed)
      let modes: [ComparisonMode] = [.exact, .ignoreAllWhitespace, .ignoreWhitespaceAmount]
      let driver = try startSearch(in: controller)
      for step in 0..<24 {
        let comment = Comment(rawValue: "seed \(Self.seed), step \(step)")
        let typed = Self.rare(Self.randomUnchangedLine(using: &generator))
        switch Int.random(in: 0..<4, using: &generator) {
        case 0:
          var options = controller.comparisonOptions
          options.mode = modes.randomElement(using: &generator) ?? .exact
          let switching = Task { [options] in await controller.switchComparison(to: options) }
          try driver.type(typed)
          await switching.value
        case 1:
          let lineCount = Bool.random(using: &generator) ? Self.lineCount : Self.lineCount * 3 / 4
          try Data(Self.newerFile(prefix: lineCount).utf8).write(to: new)
          let reloading = Task { await controller.diskWatch.reloadChangedFiles() }
          try driver.type(typed)
          await reloading.value
        case 2 where controller.allowsUndo && (undoManager.canUndo || undoManager.canRedo):
          if undoManager.canUndo && (Bool.random(using: &generator) || !undoManager.canRedo) {
            undoManager.undo()
          } else {
            undoManager.redo()
          }
          try driver.type(typed)
          await controller.comparisonSwitcher.bringingBack?.value
        default:
          try driver.type(Self.common)
          try driver.type(typed)
        }
        #expect(!controller.comparisonSwitcher.isComparing, comment)
        try await expectMatches(
          of: Self.rare(Self.randomUnchangedLine(using: &generator)), with: driver)
      }
    }
  }
}
