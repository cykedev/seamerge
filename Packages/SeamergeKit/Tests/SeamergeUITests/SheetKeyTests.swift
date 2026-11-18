import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// The keys of the sheets of a session window: Return chooses the default button; Escape and
/// Command-Period choose Cancel.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SheetKeyTests {
  /// A key as the keyboard sends it.
  struct Key: Sendable, CustomTestStringConvertible {
    let characters: String
    let code: UInt16
    let modifiers: NSEvent.ModifierFlags

    static let carriageReturn = Key(characters: "\r", code: 36, modifiers: [])
    static let escape = Key(characters: "\u{1B}", code: 53, modifiers: [])
    static let commandPeriod = Key(characters: ".", code: 47, modifiers: .command)
    static let commandD = Key(characters: "d", code: 2, modifiers: .command)

    var testDescription: String {
      switch code {
      case 36: "Return"
      case 53: "Escape"
      case 2: "Command-D"
      default: "Command-Period"
      }
    }
  }

  /// Shows the sheet that `ask` puts up on a window of its own, presses `key` and returns the
  /// answer.
  ///
  /// Escape, Command-Period and Command-D go through the app, as the keyboard's do. Return is a
  /// key equivalent, which the app gives only to the key window, and a window without a screen
  /// never is one; the button that holds Return is pressed instead.
  private func answer<Answer: Sendable>(
    pressing key: Key, to ask: @escaping @MainActor (SessionSheets, NSWindow) async -> Answer
  ) async throws -> Answer {
    let window = Self.window()
    defer { window.close() }
    let answer = Task { await ask(SessionSheets(), window) }
    var turns = 0
    while window.attachedSheet == nil && turns < 1000 {
      await Task.yield()
      turns += 1
    }
    let sheet = try #require(window.attachedSheet)
    let buttons = Self.buttons(in: try #require(sheet.contentView))
    if key.code == Key.carriageReturn.code {
      // The window gives Return to its default button.
      let button = try #require(
        sheet.defaultButtonCell, "\(buttons.map { ($0.title, $0.keyEquivalent) })")
      button.performClick(nil)
    } else {
      let event = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: key.modifiers, timestamp: 0,
          windowNumber: sheet.windowNumber, context: nil, characters: key.characters,
          charactersIgnoringModifiers: key.characters, isARepeat: false, keyCode: key.code))
      NSApplication.shared.sendEvent(event)
      if window.attachedSheet != nil {
        _ = sheet.performKeyEquivalent(with: event)
      }
    }
    if window.attachedSheet != nil {
      Issue.record("The sheet ignored \(key.testDescription)")
      buttons.last?.performClick(nil)
    }
    return await answer.value
  }

  /// A window for a sheet to hang on, which turns transparent with its sheet once it shows.
  private static func window() -> NSWindow {
    TransparentWindows.turnOn()
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    return window
  }

  /// The texts that the sheet `ask` puts up shows, after which Escape closes it.
  private func texts<Answer: Sendable>(
    of ask: @escaping @MainActor (SessionSheets, NSWindow) async -> Answer
  ) async throws -> [String] {
    let window = Self.window()
    defer { window.close() }
    let answer = Task { await ask(SessionSheets(), window) }
    var turns = 0
    while window.attachedSheet == nil && turns < 1000 {
      await Task.yield()
      turns += 1
    }
    let sheet = try #require(window.attachedSheet)
    let content = try #require(sheet.contentView)
    let texts = Self.fields(in: content).map(\.stringValue) + Self.buttons(in: content).map(\.title)
    Self.buttons(in: content).last?.performClick(nil)
    _ = await answer.value
    return texts
  }

  @Test func sheetsNameGitOnlyWhereGitWaits() async throws {
    let mentionsGit = { (texts: [String]) in texts.contains { $0.contains("Git") } }

    for caller in [WaitingCaller.commandLine, nil] {
      let closing = try await texts {
        await $0.confirmClosing("story.txt", openConflictCount: 1, caller: caller, in: $1)
      }
      #expect(!mentionsGit(closing), "\(String(describing: caller))")
    }
    #expect(
      !mentionsGit(
        try await texts {
          await $0.confirmSavingWithOpenConflicts(2, gitTakesItAsResolved: false, in: $1)
        }))
    #expect(
      !mentionsGit(
        try await texts {
          await $0.confirmLeavingUnresolved(
            "story.txt", discarding: 1, gitPutsBackTheFile: false, in: $1)
        }))

    #expect(
      mentionsGit(
        try await texts {
          await $0.confirmClosing("story.txt", openConflictCount: 1, caller: .git, in: $1)
        }))
    #expect(
      mentionsGit(
        try await texts {
          await $0.confirmSavingWithOpenConflicts(2, gitTakesItAsResolved: true, in: $1)
        }))
    #expect(
      mentionsGit(
        try await texts {
          await $0.confirmLeavingUnresolved(
            "story.txt", discarding: 1, gitPutsBackTheFile: true, in: $1)
        }))
  }

  /// The text fields in `view` and its descendants.
  private static func fields(in view: NSView) -> [NSTextField] {
    view.subviews.flatMap { subview in
      (subview as? NSTextField).map { [$0] } ?? fields(in: subview)
    }
  }

  /// The buttons in `view` and its descendants.
  private static func buttons(in view: NSView) -> [NSButton] {
    view.subviews.flatMap { subview in
      (subview as? NSButton).map { [$0] } ?? buttons(in: subview)
    }
  }

  /// The sheets whose default button is Cancel, which keeps what would be lost; each tells
  /// whether to go ahead.
  static let cautiousSheets: [@MainActor (SessionSheets, NSWindow) async -> Bool] = [
    {
      await $0.confirmLeavingUnresolved(
        "story.txt", discarding: 2, gitPutsBackTheFile: true, in: $1)
    },
    { await $0.confirmDiscarding(3, in: $1) },
    { await $0.confirmResettingAll(discardingHandwritingIn: 2, in: $1) },
    { await $0.confirmReloading("main", discarding: 1, in: $1) },
    { await $0.confirmChangingFiles(discarding: 1, in: $1) },
  ]

  @Test(arguments: [Key.carriageReturn, .escape, .commandPeriod])
  func everyKeyOfASheetThatWouldLoseWorkKeepsIt(key: Key) async throws {
    for (index, ask) in Self.cautiousSheets.enumerated() {
      let goesAhead = try await answer(pressing: key, to: ask)
      #expect(!goesAhead, "sheet \(index)")
    }
  }

  @Test func sheetBeforeSavingWithOpenConflictsGoesOnWithReturnAndCancelsWithTheOthers()
    async throws
  {
    let ask: @MainActor (SessionSheets, NSWindow) async -> OpenConflictsChoice = {
      await $0.confirmSavingWithOpenConflicts(2, gitTakesItAsResolved: true, in: $1)
    }
    #expect(try await answer(pressing: .carriageReturn, to: ask) == .goToNextConflict)
    #expect(try await answer(pressing: .escape, to: ask) == .cancel)
    #expect(try await answer(pressing: .commandPeriod, to: ask) == .cancel)
  }

  @Test func sheetBeforeClosingSavesWithReturnDiscardsWithCommandDAndCancelsWithTheOthers()
    async throws
  {
    let ask: @MainActor (SessionSheets, NSWindow) async -> UnsavedChangesChoice = {
      await $0.confirmClosing("story.txt", openConflictCount: 1, caller: .git, in: $1)
    }
    #expect(try await answer(pressing: .carriageReturn, to: ask) == .save)
    #expect(try await answer(pressing: .commandD, to: ask) == .discard)
    #expect(try await answer(pressing: .escape, to: ask) == .cancel)
    #expect(try await answer(pressing: .commandPeriod, to: ask) == .cancel)
  }
}
