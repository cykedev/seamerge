import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// Checks what the window Keyboard Shortcuts lists for each kind of window.
@MainActor
@Suite struct ShortcutOverviewTests {
  @Test func mergeListsItsMenusWithGoFirstAndEveryShortcutOfTheMenus() {
    let overview = ShortcutOverview(kind: .merge)
    #expect(overview.groups.map(\.menu) == [.go, .merge, .compare, .view, .file])
    for group in overview.groups {
      for entry in group.entries {
        let key = entry.command.keyEquivalent(in: .merge)
        #expect((entry.shortcut != nil) == (key != nil), "\(entry.command)")
      }
    }
    let listed = Set(overview.groups.flatMap(\.entries).map(\.command))
    // The Edit menu holds the standard commands of finding, which the overview leaves out as it
    // leaves out Copy.
    let editCommands = Set(SessionCommand.groups(in: .edit).joined())
    let withKeys = SessionCommand.allCases.filter {
      !editCommands.contains($0)
        && ($0.keyEquivalent(in: .merge) != nil || !$0.blockModeKeys.isEmpty)
    }
    #expect(Set(withKeys).subtracting(listed).isEmpty)
    #expect(listed.isDisjoint(with: editCommands))
  }

  @Test func shortcutsAreSpelledAsTheMenusShowThem() throws {
    let entries = ShortcutOverview(kind: .merge).groups.flatMap(\.entries)
    let entry = { (command: SessionCommand) in entries.first { $0.command == command } }
    #expect(try #require(entry(.nextChange)).shortcut == "⌥⇧⌘↓")
    #expect(try #require(entry(.nextChange)).singleKeys == "↓")
    #expect(try #require(entry(.useA)).singleKeys == "1 or ←")
    #expect(try #require(entry(.previousPane)).singleKeys == "⇧⇥")
    #expect(try #require(entry(.resetChange)).shortcut == "⌥⌘⌫")
    #expect(try #require(entry(.toggleSourceA)).title == "Toggle A")
    #expect(try #require(entry(.goToLine)).singleKeys == nil)
  }

  @Test func eachEntryIsSpokenAsOneSentence() throws {
    let entries = ShortcutOverview(kind: .merge).groups.flatMap(\.entries)
    let entry = { (command: SessionCommand) in entries.first { $0.command == command } }
    #expect(try #require(entry(.useA)).spokenDescription == "Use A, ⌘1, or 1 or ←")
    #expect(try #require(entry(.goToLine)).spokenDescription == "Go to Line…, ⌘L")
    #expect(try #require(entry(.firstChange)).spokenDescription == "First Change, ↖")
  }

  @Test func noteOnSingleKeysSpeaksOfTheResultOnlyInAMerge() {
    #expect(ShortcutOverview.singleKeyNote(for: .merge).contains("result"))
    #expect(!ShortcutOverview.singleKeyNote(for: .diff).contains("result"))
  }

  @Test func comparisonLeavesOutConflictsAndDecisionsAndListsTheFiles() {
    let overview = ShortcutOverview(kind: .diff)
    #expect(!overview.groups.map(\.menu).contains(.merge))
    let commands = Set(overview.groups.flatMap(\.entries).map(\.command))
    for command in [
      SessionCommand.nextConflict, .previousConflict, .toggleBase, .toggleResultMaximized,
      .leaveUnresolved,
    ] {
      #expect(!commands.contains(command), "\(command)")
    }
    #expect(commands.isSuperset(of: [.nextFile, .previousFile, .skipRemainingFiles]))
    let nextChange = overview.groups.flatMap(\.entries).first { $0.command == .nextChange }
    #expect(nextChange?.shortcut == "⌥⌘↓")
  }

  @Test func arrangementsStandInTheViewGroupWithTheirShortcuts() throws {
    func view(_ kind: Session.Kind) -> [ShortcutOverview.Entry] {
      ShortcutOverview(kind: kind).groups.first { $0.menu == .view }?.entries ?? []
    }
    let comparison = view(.diff).filter { $0.command.lineArrangement != nil }
    #expect(comparison.map(\.title) == ["Aligned Lines", "Connected Sides", "Single Column"])
    #expect(comparison.map(\.shortcut) == ["⌥⌘A", "⌥⇧⌘A", "⌥⌘U"])
    // A merge has no single column.
    let merge = view(.merge).filter { $0.command.lineArrangement != nil }
    #expect(merge.map(\.title) == ["Aligned Lines", "Connected Sides"])
  }

  @Test func windowStartsWithTheKindOfTheWindowInFrontAndFitsItsContent() throws {
    let controller = ShortcutOverviewWindowController(kind: .diff)
    let window = try #require(controller.window)
    defer { window.close() }
    #expect(window.title == "Keyboard Shortcuts")
    #expect(!window.styleMask.contains(.resizable))
    #expect(window.contentView?.fittingSize.width ?? 0 > 600)
  }
}
