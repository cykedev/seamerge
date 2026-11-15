import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// The page Ignored Text of Settings: rules kept over closing the window, warnings with their
/// reason, Duplicate, the keys of the table, undo, and the field that tries the selected rule.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct IgnoredTextPageTests {
  /// The window Settings for `settings` with the page Ignored Text in view.
  private func page(
    for settings: UserSettings
  ) throws -> (controller: SettingsWindowController, page: IgnoredTextViewController) {
    let controller = SettingsWindowController(
      settings: settings, updates: nil, displayOptions: DisplayOptions(reducesMotion: true))
    controller.tabs.selectedTabViewItemIndex = 1
    let window = try #require(controller.window)
    window.contentView?.layoutSubtreeIfNeeded()
    return (controller, controller.ignoredText)
  }

  @Test func windowHasThePagesGeneralAndIgnoredTextWithASizeAndNameEach() throws {
    let (controller, page) = try page(for: .private())
    let window = try #require(controller.window)
    #expect(controller.tabs.tabViewItems.map(\.label) == ["General", "Ignored Text"])
    #expect(window.title == "Ignored Text")
    let general = try #require(controller.tabs.tabViewItems.first?.viewController)
    // The tab view controller gives the window the size the page in view prefers.
    #expect(page.preferredContentSize == page.view.fittingSize)
    #expect(page.preferredContentSize.width == general.preferredContentSize.width)
    #expect(page.preferredContentSize.height < general.preferredContentSize.height)

    controller.tabs.selectedTabViewItemIndex = 0

    #expect(window.title == "General")
  }

  @Test func rulesOutlastClosingAndOpeningSettings() throws {
    let defaults = UserDefaults.privateSuite()
    let (controller, page) = try page(for: UserSettings(defaults: defaults))
    page.addRule(nil)
    let row = page.tableView.selectedRow
    page.edit(customRule: 0, name: "Build number", pattern: #"Build \d+"#)
    page.toggleRule(atRow: 1)
    #expect(row == 3)
    controller.close()

    let (_, reopened) = try self.page(for: UserSettings(defaults: defaults))

    #expect(reopened.tableView.numberOfRows == 4)
    #expect(reopened.rule(at: 3) == IgnoreRule(name: "Build number", pattern: #"Build \d+"#))
    #expect(reopened.rule(at: 1)?.isEnabled == true)
    let toggle = try #require(
      reopened.tableView.view(atColumn: 0, row: 1, makeIfNecessary: true)?.subviews.first
        as? NSButton)
    #expect(toggle.state == .on)
    let name = try #require(field(inColumn: 1, row: 3, of: reopened))
    #expect(name.stringValue == "Build number")
  }

  @Test func invalidPatternShowsAWarningWithItsReasonAndTakesNoEffect() async throws {
    let settings = UserSettings.private()
    settings.customIgnoreRules = [
      IgnoreRule(name: "Broken", pattern: #"(\d+"#),
      IgnoreRule(name: "Everything", pattern: ".*"),
      IgnoreRule(name: "New", pattern: ""),
    ]
    let (_, page) = try page(for: settings)

    let reasons = (3..<6).map { warning(inRow: $0, of: page) }
    #expect(reasons[0] == "The pattern isn’t valid, so the rule ignores nothing.")
    #expect(reasons[1] == "The pattern also matches empty text, so the rule ignores nothing.")
    #expect(reasons[2] == nil, "an empty pattern is a rule still being written")
    #expect(warning(inRow: 0, of: page) == nil)

    page.tableView.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)
    page.trialField.text = "Build 12"
    await page.trialTask?.value
    #expect(page.trialField.markedRanges.isEmpty)
    #expect(page.reasonLabel.stringValue == reasons[0])

    let session = try await Session.diff(
      old: SourceFile(bytes: Data("Build 12\n".utf8), label: "old"),
      new: SourceFile(bytes: Data("Build 13\n".utf8), label: "new"),
      ignoring: settings.ignoreRules)
    #expect(session.blocks.map(\.kind) == [.changed])
  }

  @Test func typedPatternWarnsAndIsTriedBeforeItIsKept() async throws {
    let settings = UserSettings.private()
    settings.customIgnoreRules = [IgnoreRule(name: "Build", pattern: #"\d+"#)]
    let (_, page) = try page(for: settings)
    page.tableView.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)
    page.trialField.text = "Build 12"

    page.patternIsBeingTyped("(")
    page.reloadWarning(ofRow: 3)
    #expect(warning(inRow: 3, of: page) == IgnoreRule.Problem.invalidPattern.reason)
    #expect(page.trialField.markedRanges.isEmpty)

    page.patternIsBeingTyped("B[a-z]+")
    await page.trialTask?.value
    #expect(warning(inRow: 3, of: page) == IgnoreRule.Problem.invalidPattern.reason)
    page.reloadWarning(ofRow: 3)
    #expect(warning(inRow: 3, of: page) == nil)
    #expect(page.trialField.markedRanges == [0..<5])
    #expect(settings.customIgnoreRules.first?.pattern == #"\d+"#)
  }

  @Test func duplicateMakesAnOwnCopyThatCanBeChanged() throws {
    let settings = UserSettings.private()
    settings.enabledBuiltInIgnoreRules = [.uuids]
    let (controller, page) = try page(for: settings)
    page.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    #expect(!page.removeButton.isEnabled, "a rule that comes with the app stays")
    #expect(try #require(field(inColumn: 1, row: 1, of: page)).isEditable == false)

    page.duplicateRule(nil)

    #expect(
      settings.customIgnoreRules == [
        IgnoreRule(name: "UUIDs copy", pattern: BuiltInIgnoreRule.uuids.pattern)
      ])
    #expect(page.tableView.selectedRow == 3)
    #expect(page.removeButton.isEnabled)
    let name = try #require(field(inColumn: 1, row: 3, of: page))
    let pattern = try #require(field(inColumn: 2, row: 3, of: page))
    #expect(name.isEditable && pattern.isEditable)
    #expect(controller.window?.firstResponder === name.currentEditor(), "the name is edited")
  }

  @Test func contextMenuOffersDuplicateAndRemovesOnlyOwnRules() throws {
    let settings = UserSettings.private()
    settings.customIgnoreRules = [IgnoreRule(name: "Own", pattern: "x+")]
    let (_, page) = try page(for: settings)
    let menu = try #require(page.tableView.menu)

    page.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    #expect(titles(of: menu, clickedRow: 0, in: page) == ["Duplicate"])
    #expect(titles(of: menu, clickedRow: 3, in: page) == ["Duplicate", "Remove Rule"])
  }

  @Test func keysOfTheTableToggleEditAndRemove() throws {
    let settings = UserSettings.private()
    settings.customIgnoreRules = [
      IgnoreRule(name: "One", pattern: "1"), IgnoreRule(name: "Two", pattern: "2"),
    ]
    let (controller, page) = try page(for: settings)
    let window = try #require(controller.window)
    let table = page.tableView
    window.makeFirstResponder(table)

    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    table.keyDown(with: try event(" ", in: window))
    #expect(settings.enabledBuiltInIgnoreRules == [.timestamps])
    table.keyDown(with: try event("\u{7f}", in: window))
    #expect(settings.ignoreRules.count == 5, "Delete leaves a rule that comes with the app")

    table.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)
    table.keyDown(with: try event("\u{7f}", in: window))
    #expect(settings.customIgnoreRules.map(\.name) == ["Two"])
    #expect(table.selectedRow == 3, "the next rule is selected")

    table.keyDown(with: try event("\r", in: window))
    let name = try #require(field(inColumn: 1, row: 3, of: page))
    #expect(window.firstResponder === name.currentEditor())
  }

  @Test func tabMovesFromTheNameToThePatternAndBack() throws {
    let settings = UserSettings.private()
    settings.customIgnoreRules = [IgnoreRule(name: "One", pattern: "1")]
    let (controller, page) = try page(for: settings)
    let window = try #require(controller.window)
    page.tableView.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)
    page.editName(ofRow: 3)
    let editor = try #require(window.firstResponder as? NSTextView)
    editor.insertText("Uno", replacementRange: editor.selectedRange())

    editor.doCommand(by: #selector(NSResponder.insertTab(_:)))

    #expect(settings.customIgnoreRules.first?.name == "Uno")
    let pattern = try #require(field(inColumn: 2, row: 3, of: page))
    #expect(window.firstResponder === pattern.currentEditor())
    let patternEditor = try #require(window.firstResponder as? NSTextView)
    patternEditor.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
    let name = try #require(field(inColumn: 1, row: 3, of: page))
    #expect(window.firstResponder === name.currentEditor())
  }

  @Test func everyChangeIsAStepOfUndoOfTheWindow() throws {
    let settings = UserSettings.private()
    settings.customIgnoreRules = [IgnoreRule(name: "One", pattern: "1")]
    let (controller, page) = try page(for: settings)
    let undoManager = try #require(controller.window?.undoManager)
    undoManager.groupsByEvent = false
    page.tableView.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)

    undoManager.beginUndoGrouping()
    page.removeRule(nil)
    undoManager.endUndoGrouping()
    #expect(settings.customIgnoreRules.isEmpty)
    #expect(undoManager.undoMenuItemTitle == "Undo Remove Rule")
    #expect(!page.note.isHidden, "the note returns without own rules")

    undoManager.undo()
    #expect(settings.customIgnoreRules == [IgnoreRule(name: "One", pattern: "1")])
    #expect(page.tableView.selectedRow == 3)
    #expect(page.note.isHidden)
  }

  @Test func trialMarksExactlyWhatTheSelectedRuleLeavesOut() async throws {
    let settings = UserSettings.private()
    settings.customIgnoreRules = [IgnoreRule(name: "Build", pattern: #"Build \d+"#)]
    let (_, page) = try page(for: settings)
    let text = "2026-11-15 13:40:23 Build 4711\nBuild 12 at 09:00:00\nDone\n"
    page.trialField.text = text
    #expect(page.trialField.markedRanges.isEmpty, "nothing is selected")

    for row in [0, 3] {
      page.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      await page.trialTask?.value
      let rule = try #require(page.rule(at: row))
      let trial = await rule.trial(on: text, mode: settings.comparisonMode)
      #expect(trial == .matches(page.trialField.markedRanges))
      #expect(markedRanges(in: page.trialField) == page.trialField.markedRanges)
    }
    #expect(page.trialField.markedRanges == [20..<30, 31..<39])

    page.trialField.text = "Build 1"
    #expect(page.trialField.markedRanges.isEmpty, "marks go with the text they were found in")
    await page.trialTask?.value
    #expect(page.trialField.markedRanges == [0..<7])
  }

  @Test func trialOfAPatternThatTakesTooLongSaysWhyAndWarns() async throws {
    let settings = UserSettings.private()
    settings.customIgnoreRules = [IgnoreRule(name: "Slow", pattern: #"(a+)+$"#)]
    let (_, page) = try page(for: settings)
    page.tableView.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)

    page.trialField.text = String(repeating: "a", count: 40) + "!"
    await page.trialTask?.value

    #expect(page.reasonLabel.stringValue == IgnoreRule.Problem.exceedsTimeLimit.reason)
    #expect(warning(inRow: 3, of: page) == IgnoreRule.Problem.exceedsTimeLimit.reason)
  }

  @Test func controlsHaveNamesForVoiceOver() throws {
    let (_, page) = try page(for: .private())
    #expect(page.addButton.accessibilityLabel() == "Add Rule")
    #expect(page.removeButton.accessibilityLabel() == "Remove Rule")
    #expect(page.trialField.textView.accessibilityLabel() == "Try the selected rule:")
    #expect(page.tableView.accessibilityLabel() == "Ignore Rules")
    let toggle = try #require(
      page.tableView.view(atColumn: 0, row: 2, makeIfNecessary: true)?.subviews.first
        as? NSButton)
    #expect(toggle.accessibilityLabel() == "Memory Addresses")
  }

  /// The text field of the cell in `column` and `row`.
  private func field(inColumn column: Int, row: Int, of page: IgnoredTextViewController)
    -> NSTextField?
  {
    page.tableView.view(atColumn: column, row: row, makeIfNecessary: true)?.subviews
      .compactMap { $0 as? NSTextField }.first
  }

  /// The reason the warning in `row` gives, or `nil` while the row shows no warning.
  private func warning(inRow row: Int, of page: IgnoredTextViewController) -> String? {
    let warning = page.tableView.view(atColumn: 2, row: row, makeIfNecessary: true)?.subviews
      .compactMap { $0 as? NSImageView }.first
    guard let warning, !warning.isHidden else { return nil }
    #expect(warning.image?.accessibilityDescription == warning.toolTip)
    return warning.toolTip
  }

  /// The titles of the context menu of the table, opened on `row`.
  private func titles(
    of menu: NSMenu, clickedRow row: Int, in page: IgnoredTextViewController
  ) -> [String] {
    page.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    page.fillContextMenu(menu, forRow: row)
    return menu.items.map(\.title)
  }

  /// The ranges of the text of `field` that its text layout manager draws marked.
  private func markedRanges(in field: RuleTrialField) -> [Range<Int>] {
    guard let layoutManager = field.textView.textLayoutManager,
      let storage = layoutManager.textContentManager
    else { return [] }
    var ranges: [Range<Int>] = []
    layoutManager.enumerateRenderingAttributes(
      from: layoutManager.documentRange.location, reverse: false
    ) { _, attributes, range in
      if attributes[.backgroundColor] != nil {
        let start = storage.offset(from: storage.documentRange.location, to: range.location)
        let end = storage.offset(from: storage.documentRange.location, to: range.endLocation)
        ranges.append(start..<end)
      }
      return true
    }
    return ranges
  }
}
