import AppKit
import MergeModel
import SyntaxKit
import Testing

@testable import SeamergeUI

/// The window of a comparison with text pasted from the clipboard: how it names that side, that
/// changes are copied from it but never into it, the language it colors in, Change Files, and
/// that the copy goes with the window.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct PastedTextWindowTests {
  /// A side of a comparison in a test: text pasted at a time, or a file with a name.
  private enum Side {
    case pasted(String, at: Date)
    case file(String, named: String)
  }

  /// The clipboard and files of a test, and the comparison of two of its sides.
  @MainActor
  private final class Fixture {
    let clipboard = Clipboard()
    let files: SampleFiles
    let comparison: FileComparison

    init(left: Side, right: Side) throws {
      files = try SampleFiles()
      var pasted: [URL: PastedText] = [:]
      var urls: [URL] = []
      for side in [left, right] {
        switch side {
        case .pasted(let text, let date):
          let kept = try clipboard.cache.keep(text, pastedAt: date)
          pasted[kept.url] = kept
          urls.append(kept.url)
        case .file(let text, let name):
          let url = files.folder.appending(path: name)
          try Data(text.utf8).write(to: url)
          urls.append(url)
        }
      }
      comparison = FileComparison(left: urls[0], right: urls[1], pastedTexts: pasted)
    }

    /// The window of the comparison, as the app opens it from the sheet Compare Files, with
    /// `undoManager`.
    func window(undoManager: UndoManager = UndoManager()) async throws -> SessionWindowController {
      let session = try await Session.loadDiff(
        old: comparison.sessionFile(at: comparison.left),
        new: comparison.sessionFile(at: comparison.right), mode: .windowDefault)
      return try Windows.controller(
        for: session, context: SessionContext(pastedTexts: comparison.pastedTexts),
        undoManager: undoManager)
    }
  }

  private static let earlier = Date(timeIntervalSinceReferenceDate: 800_000_000)
  private static let later = earlier.addingTimeInterval(180)

  private static func time(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }

  @Test func sideFromTheClipboardIsCalledClipboardEverywhere() async throws {
    let fixture = try Fixture(
      left: .pasted("one\ntwo\n", at: Self.earlier), right: .file("one\nthree\n", named: "b.txt"))
    let controller = try await fixture.window()
    defer { controller.window?.close() }
    let header = try #require(controller.presentation.headers[.a])

    #expect(header.name == "Clipboard")
    #expect(header.spokenName.contains("Clipboard"))
    #expect(header.details.location == "Clipboard")
    #expect(controller.window?.title == "Clipboard ↔ b.txt")
    #expect(controller.headerMenu(for: .a) == nil)
    #expect(controller.headerMenu(for: .b) != nil)
  }

  @Test func twoSidesFromTheClipboardCarryTheirTimes() async throws {
    let fixture = try Fixture(
      left: .pasted("one\n", at: Self.earlier), right: .pasted("two\n", at: Self.later))
    let controller = try await fixture.window()
    defer { controller.window?.close() }

    let names = [Role.a, .b].compactMap { controller.presentation.headers[$0]?.name }
    #expect(
      names == ["Clipboard \(Self.time(Self.earlier))", "Clipboard \(Self.time(Self.later))"])
    #expect(controller.window?.title == "\(names[0]) ↔ \(names[1])")
  }

  @Test func changesAreCopiedFromTheClipboardIntoAFileButNeverIntoIt() async throws {
    let fixture = try Fixture(
      left: .pasted("one\nfrom the web\n", at: Self.earlier),
      right: .file("one\nmine\n", named: "config.txt"))
    let controller = try await fixture.window()
    defer { controller.window?.close() }
    controller.presentation.jump(to: 0)

    #expect(controller.canPerform(.copyToRight))
    #expect(!controller.canPerform(.copyToLeft))
    #expect(!controller.canPerform(.openInEditor))
    controller.copyToRight(nil)
    await controller.copying?.value

    #expect(
      controller.presentation.changes.session.inputs.b.bytes == Data("one\nfrom the web\n".utf8))
    #expect(controller.hasUnsavedChanges)

    let other = try Fixture(
      left: .file("one\nmine\n", named: "config.txt"),
      right: .pasted("one\nfrom the web\n", at: Self.earlier))
    let reversed = try await other.window()
    defer { reversed.window?.close() }
    reversed.presentation.jump(to: 0)
    #expect(!reversed.canPerform(.copyToRight))
    #expect(reversed.canPerform(.copyToLeft))
  }

  @Test func languageFollowsTheOtherSideAndElseIsPlainText() async throws {
    let fixture = try Fixture(
      left: .file("let a = 1\n", named: "Values.swift"),
      right: .pasted("let a = 2\n", at: Self.earlier))
    let controller = try await fixture.window()
    defer { controller.window?.close() }
    #expect(controller.detectedLanguage.name == "Swift")

    let both = try Fixture(
      left: .pasted("#!/bin/sh\n", at: Self.earlier), right: .pasted("#!/bin/zsh\n", at: Self.later)
    )
    let plain = try await both.window()
    defer { plain.window?.close() }
    #expect(plain.detectedLanguage == .plainText)
  }

  @Test func changeFilesShowsTheSideFromTheClipboard() async throws {
    let fixture = try Fixture(
      left: .pasted("one\n", at: Self.earlier), right: .file("two\n", named: "b.txt"))
    let controller = try await fixture.window()
    defer { controller.window?.close() }

    controller.changeFiles(nil)

    let sheet = try #require(controller.changeFilesSheet)
    let field = try #require(sheet.fields[.left])
    #expect(field.accessibilityValue() as? String == "Clipboard, 1 line")
    #expect(sheet.selection.comparison == fixture.comparison)
    sheet.swapSides(nil)
    let swapped = try #require(sheet.selection.comparison)
    sheet.cancelOperation(nil)

    try await controller.changeFiles(to: swapped)
    #expect(controller.presentation.headers[.b]?.name == "Clipboard")
    #expect(controller.presentation.headers[.a]?.name == "b.txt")
    #expect(try fixture.clipboard.copies.count == 1)
  }

  /// Change Files that puts a file in place of the side from the clipboard removes its copy at
  /// once; undo shows the text again, still never written.
  @Test func changeFilesInPlaceOfTheClipboardRemovesItsCopy() async throws {
    let fixture = try Fixture(
      left: .pasted("one\n", at: Self.earlier), right: .file("two\n", named: "b.txt"))
    let undoManager = UndoManager()
    let controller = try await fixture.window(undoManager: undoManager)
    defer { controller.window?.close() }
    let file = fixture.files.folder.appending(path: "a.txt")
    try Data("three\n".utf8).write(to: file)

    try await controller.changeFiles(
      to: FileComparison(left: file, right: fixture.comparison.right))

    #expect(try fixture.clipboard.copies.isEmpty)
    #expect(controller.context.pastedTexts.isEmpty)
    #expect(controller.presentation.headers[.a]?.name == "a.txt")

    undoManager.undo()
    await controller.comparisonSwitcher.bringingBack?.value
    controller.presentation.jump(to: 0)
    #expect(controller.presentation.headers[.a]?.name == "Clipboard")
    #expect(!controller.canPerform(.copyToLeft))
  }

  @Test func copyGoesWithTheWindow() async throws {
    let fixture = try Fixture(
      left: .pasted("one\n", at: Self.earlier), right: .file("two\n", named: "b.txt"))
    let controller = try await fixture.window()
    #expect(try fixture.clipboard.copies.count == 1)

    controller.close()

    #expect(try fixture.clipboard.copies.isEmpty)
  }

  @Test func leftoversOfAnEarlierRunGoAndCopiesMadeSinceStay() async throws {
    let clipboard = Clipboard()
    let leftover = try clipboard.cache.keep("old\n", pastedAt: Self.earlier)
    let start = Date.now.addingTimeInterval(1)
    try FileManager.default.setAttributes(
      [.creationDate: start.addingTimeInterval(-60)],
      ofItemAtPath: leftover.url.deletingLastPathComponent().path(percentEncoded: false))
    let fresh = try clipboard.cache.keep("new\n", pastedAt: .now)
    try FileManager.default.setAttributes(
      [.creationDate: start.addingTimeInterval(1)],
      ofItemAtPath: fresh.url.deletingLastPathComponent().path(percentEncoded: false))

    await clipboard.cache.removeLeftovers(madeBefore: start)

    #expect(
      try clipboard.copies.map(\.lastPathComponent)
        == [fresh.url.deletingLastPathComponent().lastPathComponent])
  }
}
