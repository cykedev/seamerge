import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Compare ▸ Use Ignore Rules in a window: when it is valid, what switching it does, how the
/// window follows the rules of Settings, the subtitle, and the places Show Ignored Changes shows.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct IgnoreRulesWindowTests {
  /// A log of two runs: the times differ on every line, and one step really changed.
  static let old = """
    2026-11-14 09:12:01 start
    2026-11-14 09:12:02 compile Session.swift
    2026-11-14 09:12:05 link
    2026-11-14 09:12:06 done

    """
  static let new = """
    2026-11-15 13:40:23 start
    2026-11-15 13:40:24 compile Session.swift
    2026-11-15 13:40:27 sign
    2026-11-15 13:40:28 done

    """

  /// Settings with the rule for timestamps switched on.
  private static func settingsWithTimestamps() -> UserSettings {
    let settings = UserSettings.private()
    settings.enabledBuiltInIgnoreRules = [.timestamps]
    return settings
  }

  /// The comparison of the two logs as a window of `settings` opens it.
  private static func diff(
    _ old: String = old, _ new: String = new, settings: UserSettings
  ) async throws -> Session {
    try await Session.diff(
      old: SourceFile(bytes: Data(old.utf8), label: "build.log"),
      new: SourceFile(bytes: Data(new.utf8), label: "build.log"), mode: .windowDefault,
      ignoring: settings.ignoreRules)
  }

  /// The menu item of Use Ignore Rules, validated by `controller`.
  private static func validatedItem(
    in controller: SessionWindowController
  ) -> (item: NSMenuItem, isValid: Bool) {
    let item = NSMenuItem(
      title: SessionCommand.toggleIgnoreRules.title,
      action: SessionCommand.toggleIgnoreRules.action, keyEquivalent: "")
    let isValid = controller.validateUserInterfaceItem(item)
    return (item, isValid)
  }

  @Test func commandStandsInTheCompareMenuWithoutAShortcut() {
    #expect(SessionCommand.groups(in: .compare).contains([.toggleIgnoreRules]))
    #expect(SessionCommand.toggleIgnoreRules.title == "Use Ignore Rules")
    #expect(SessionCommand.toggleIgnoreRules.keyEquivalent(in: .diff) == nil)
  }

  @Test func commandIsValidOnlyWithARuleThatTakesEffect() async throws {
    let settings = UserSettings.private()
    let controller = try Windows.controller(
      for: try await Self.diff(settings: settings), settings: settings)
    #expect(!Self.validatedItem(in: controller).isValid)
    #expect(
      Self.validatedItem(in: controller).item.state == .on,
      "the checkmark shows that the window uses rules, also while none can take effect")

    settings.customIgnoreRules = [IgnoreRule(name: "Broken", pattern: "(")]
    #expect(!Self.validatedItem(in: controller).isValid, "an invalid rule takes no effect")

    settings.enabledBuiltInIgnoreRules = [.timestamps]
    let (item, isValid) = Self.validatedItem(in: controller)
    #expect(isValid)
    #expect(item.state == .on, "every window starts using the rules")
    #expect(item.toolTip == "Leave out the text that the rules in Settings match")
  }

  @Test func ruleWithAnEmptyPatternAloneTakesNoEffect() async throws {
    let settings = UserSettings.private()
    settings.customIgnoreRules = [IgnoreRule(name: "New", pattern: "")]
    let controller = try Windows.controller(
      for: try await Self.diff(settings: settings), settings: settings)
    let session = controller.presentation.changes.session

    #expect(!Self.validatedItem(in: controller).isValid)
    #expect(session.ignoreRuleProblems == [IgnoreRule(name: "New", pattern: ""): .invalidPattern])
    #expect(session.blocks.filter { $0.kind == .changed }.first?.lines(in: .b).count == 4)
    #expect(try #require(controller.window).subtitle == "")
  }

  @Test func renamingARuleComparesNothingAnew() async throws {
    let settings = UserSettings.private()
    settings.customIgnoreRules = [IgnoreRule(name: "Times", pattern: #"\d+:\d+:\d+"#)]
    let controller = try Windows.controller(
      for: try await Self.diff(settings: settings), settings: settings)
    let session = controller.presentation.changes.session

    settings.customIgnoreRules = [IgnoreRule(name: "Clock", pattern: #"\d+:\d+:\d+"#)]
    await controller.compareWithRequestedRules(usingIgnoreRules: nil)

    #expect(controller.presentation.changes.session.ignoreRules.map(\.name) == ["Times"])
    #expect(controller.presentation.changes.session.ignoreRules == session.ignoreRules)
  }

  @Test func commandIsInvalidInAMergeAndSaysWhy() async throws {
    let settings = Self.settingsWithTimestamps()
    let controller = try Windows.controller(
      for: try await SampleMerges.helloWorld(), settings: settings)

    let (item, isValid) = Self.validatedItem(in: controller)

    #expect(!isValid)
    #expect(item.state == .off)
    #expect(item.toolTip == "Merges always compare all text.")
    #expect(controller.requestedIgnoreRules.isEmpty)
  }

  @Test func switchingComparesAnewKeepsTheCurrentBlockAndUndoesInOneStep() async throws {
    let settings = Self.settingsWithTimestamps()
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let controller = try Windows.controller(
      for: try await Self.diff(settings: settings), undoManager: undoManager, settings: settings)
    let window = try #require(controller.window)
    let presentation = controller.presentation
    #expect(presentation.changes.blocks.filter { $0.kind == .changed }.count == 1)
    let change = try #require(presentation.changes.blocks.firstIndex { $0.kind == .changed })
    presentation.setCurrentBlock(change)
    #expect(window.subtitle == "Ignore rules applied")

    undoManager.beginUndoGrouping()
    await controller.compareWithRequestedRules(usingIgnoreRules: false)
    undoManager.endUndoGrouping()

    #expect(!controller.usesIgnoreRules)
    #expect(presentation.changes.session.ignoreRules.isEmpty)
    #expect(presentation.changes.blocks.filter { $0.kind == .changed }.count == 1)
    let current = try #require(presentation.currentBlock)
    #expect(presentation.changes.blocks[current].lines(in: .b).contains(2), "the line with sign")
    #expect(presentation.changes.blocks[current].lines(in: .b).count == 4)
    #expect(Self.validatedItem(in: controller).item.state == .off)
    #expect(window.subtitle == "")
    #expect(undoManager.undoMenuItemTitle == "Undo Change Comparison")

    undoManager.undo()
    await controller.comparisonSwitcher.bringingBack?.value
    #expect(controller.usesIgnoreRules)
    #expect(presentation.changes.session.ignoreRules == settings.ignoreRules.filter(\.isEnabled))
    #expect(window.subtitle == "Ignore rules applied")
    undoManager.redo()
    await controller.comparisonSwitcher.bringingBack?.value
    #expect(!controller.usesIgnoreRules)
  }

  @Test func comparisonFollowsTheRulesOfSettingsWithoutAStepOfUndo() async throws {
    let settings = UserSettings.private()
    let undoManager = UndoManager()
    let controller = try Windows.controller(
      for: try await Self.diff(settings: settings), undoManager: undoManager, settings: settings)
    let merge = try Windows.controller(for: try await SampleMerges.helloWorld(), settings: settings)
    let mergeSession = merge.presentation.changes.session
    #expect(controller.presentation.changes.blocks.filter { $0.kind == .changed }.count == 1)
    #expect(controller.presentation.changes.blocks.first?.lines(in: .b).count == 4)

    settings.enabledBuiltInIgnoreRules = [.timestamps]
    await controller.compareWithRequestedRules(usingIgnoreRules: nil)

    #expect(
      controller.presentation.changes.session.ignoreRules == [
        BuiltInIgnoreRule.timestamps.rule(isEnabled: true)
      ])
    #expect(controller.presentation.changes.blocks.filter { $0.kind == .changed }.count == 1)
    #expect(!undoManager.canUndo)
    await merge.compareWithRequestedRules(usingIgnoreRules: nil)
    #expect(merge.presentation.changes.session.blocks == mergeSession.blocks)
    #expect(merge.presentation.changes.session.ignoreRules.isEmpty)
  }

  @Test func changeOfTheRulesInSettingsStartsTheComparison() async throws {
    let settings = UserSettings.private()
    let controller = try Windows.controller(
      for: try await Self.diff(settings: settings), settings: settings)

    settings.enabledBuiltInIgnoreRules = [.timestamps]

    var turns = 0
    while controller.presentation.changes.session.ignoreRules.isEmpty && turns < 100_000 {
      await Task.yield()
      turns += 1
    }
    #expect(controller.presentation.changes.session.ignoreRules.count == 1)
  }

  @Test func windowThatDoesNotUseRulesStaysSoWhenTheyChange() async throws {
    let settings = Self.settingsWithTimestamps()
    let controller = try Windows.controller(
      for: try await Self.diff(settings: settings), settings: settings)
    await controller.compareWithRequestedRules(usingIgnoreRules: false)

    settings.customIgnoreRules = [IgnoreRule(name: "Steps", pattern: "sign|link")]
    await controller.compareWithRequestedRules(usingIgnoreRules: nil)

    #expect(controller.presentation.changes.session.ignoreRules.isEmpty)
  }

  @Test func subtitleNamesTheRulesOnlyWhenTheyPassedOverADifference() async throws {
    let settings = Self.settingsWithTimestamps()
    let same = try Windows.controller(
      for: try await Self.diff(
        Self.old, Self.old.replacingOccurrences(of: "link", with: "sign"),
        settings: settings),
      settings: settings)
    #expect(try #require(same.window).subtitle == "")

    let exact = try Windows.controller(
      for: try await Session.diff(
        old: SourceFile(bytes: Data(Self.old.utf8), label: "build.log"),
        new: SourceFile(bytes: Data(Self.new.utf8), label: "build.log"), mode: .exact,
        ignoring: settings.ignoreRules),
      settings: settings)
    #expect(try #require(exact.window).subtitle == "Compared exactly · Ignore rules applied")
  }

  @Test func ruleThatEmptiesTheFilesLeavesNoChangeAndTheSubtitleSaysWhy() async throws {
    let settings = Self.settingsWithTimestamps()
    let controller = try Windows.controller(
      for: try await Self.diff("10:00:00\n", "11:30:00\n12:00:00\n", settings: settings),
      settings: settings)

    #expect(controller.presentation.changes.blocks.allSatisfy { $0.kind == .unchanged })
    #expect(try #require(controller.window).subtitle == "Ignore rules applied")
  }

  @Test func showIgnoredChangesShowsThePlacesThatTheRulesMatch() async throws {
    let settings = Self.settingsWithTimestamps()
    let controller = try Windows.controller(
      for: try await Self.diff(settings: settings), settings: settings)
    #expect(controller.canPerform(.toggleIgnoredChanges))
    let a = try #require(controller.layout.sourcePane(.a))

    controller.perform(.toggleIgnoredChanges)

    let places = a.content.ignoredDifferencePlaces.map {
      (a.content.text as NSString).substring(
        with: NSRange(location: $0.lowerBound, length: $0.count))
    }
    #expect(places.contains("2026-11-14 09:12:01"))
    #expect(places.allSatisfy { $0.hasPrefix("2026-11-14 ") })
    await controller.compareWithRequestedRules(usingIgnoreRules: false)
    #expect(!controller.canPerform(.toggleIgnoredChanges), "without rules nothing is ignored")
  }

  @Test func filesReadWithTheRulesOfSettingsUseThem() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "IgnoreRulesWindowTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let (old, new) = (folder.appending(path: "old.log"), folder.appending(path: "new.log"))
    try Data(Self.old.utf8).write(to: old)
    try Data(Self.new.utf8).write(to: new)
    let settings = Self.settingsWithTimestamps()

    let session = try await Session.loadDiff(
      old: SessionFile(url: old, label: "old.log"), new: SessionFile(url: new, label: "new.log"),
      mode: settings.comparisonMode, ignoring: settings.ignoreRules)
    let controller = try Windows.controller(for: session, settings: settings)
    try Data(Self.new.replacingOccurrences(of: "sign", with: "notarize").utf8).write(to: new)
    await controller.diskWatch.reloadChangedFiles()

    let reloaded = controller.presentation.changes.session
    #expect(reloaded.ignoreRules == [BuiltInIgnoreRule.timestamps.rule(isEnabled: true)])
    #expect(reloaded.blocks.filter { $0.kind == .changed }.count == 1)
    let text = reloaded.inputs.b.bytes
    #expect(String(decoding: text, as: UTF8.self).contains("notarize"))
  }

  @Test func windowOfSeveralFilesComparesEachWithTheRulesItUses() async throws {
    let folder = try SampleCollections.folder()
    let collection = FileCollection(files: [
      try SampleCollections.file("first.log", old: Self.old, new: Self.new, in: folder),
      try SampleCollections.file("second.log", old: Self.new, new: Self.old, in: folder),
    ])
    let settings = Self.settingsWithTimestamps()
    let controller = try await Windows.controller(for: collection, settings: settings)
    let rules = [BuiltInIgnoreRule.timestamps.rule(isEnabled: true)]
    #expect(controller.presentation.changes.session.ignoreRules == rules)

    controller.showFile(at: 1)
    await controller.fileLoad?.value
    #expect(controller.presentation.changes.session.ignoreRules == rules)
    await controller.compareWithRequestedRules(usingIgnoreRules: false)
    controller.showFile(at: 0)
    await controller.fileLoad?.value

    #expect(controller.presentation.changes.session.ignoreRules.isEmpty, "read anew without rules")
  }
}
