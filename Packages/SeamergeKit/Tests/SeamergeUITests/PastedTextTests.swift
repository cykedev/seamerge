import AppKit
import MergeModel
import Synchronization
import Testing

@testable import SeamergeUI

/// Paste in the sheets of files and in the welcome window: what goes into which field, with the
/// focus and without, what Paste refuses, and how long the copy of pasted text lives.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct PastedTextTests {
  /// The item of Edit > Paste, as the menu bar of the app has it.
  private let pasteItem = NSMenuItem(
    title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")

  /// The object that Paste reaches from the focus of `window`, as the command of the menu bar
  /// finds it along the responder chain.
  private func pasteTarget(in window: NSWindow) throws -> NSResponder {
    var responder = window.firstResponder
    while let candidate = responder, !candidate.responds(to: #selector(NSText.paste(_:))) {
      responder = candidate.nextResponder
    }
    return try #require(responder)
  }

  /// Whether Paste is valid with the focus of `window`, as the menu bar asks.
  private func canPaste(in window: NSWindow) throws -> Bool {
    let target = try pasteTarget(in: window)
    return try #require(target as? any NSUserInterfaceValidations)
      .validateUserInterfaceItem(pasteItem)
  }

  /// Sends Paste along the responder chain of `window`, as ⌘V does.
  private func paste(in window: NSWindow) throws {
    #expect(try pasteTarget(in: window).tryToPerform(#selector(NSText.paste(_:)), with: nil))
  }

  /// The text of the copy of what the field `slot` of `sheet` holds.
  private func copiedText(
    in slot: FileSlot, of sheet: CompareFilesWindowController
  ) throws -> String {
    let text = try #require(sheet.selection.pastedText(in: slot))
    return String(decoding: try Data(contentsOf: text.url), as: UTF8.self)
  }

  @Test(arguments: [nil, FileSlot.right])
  func textGoesIntoTheFieldWithTheFocusOrElseTheFirstEmptyOne(focus: FileSlot?) throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture()
    let file = try files.file("a.txt")
    fixture.controller.fill([.right: file])
    if let focus {
      fixture.window.makeFirstResponder(try fixture.field(focus))
    }
    fixture.clipboard.copy("one\ntwo\n")

    #expect(try canPaste(in: fixture.window))
    try paste(in: fixture.window)

    let slot = focus ?? .left
    #expect(try copiedText(in: slot, of: fixture.controller) == "one\ntwo\n")
    #expect(fixture.files.compactMap(\.self).contains(file) == (focus == nil))
    let role = slot == .left ? "Left" : "Right"
    #expect(fixture.announcements.last == "Clipboard added as \(role)")
  }

  @Test(arguments: [nil, FileSlot.right])
  func filesGoWhereADropOnTheFieldWithTheFocusPutsThem(focus: FileSlot?) throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture()
    let (first, second) = (try files.file("first.txt"), try files.file("second.txt"))
    if let focus {
      fixture.window.makeFirstResponder(try fixture.field(focus))
    }

    fixture.clipboard.copy(files: [first])
    #expect(try canPaste(in: fixture.window))
    try paste(in: fixture.window)
    #expect(fixture.files == (focus == nil ? [first, nil] : [nil, first]))
    #expect(fixture.controller.selection.pastedTexts.isEmpty)

    fixture.clipboard.copy(files: [first, second])
    try paste(in: fixture.window)
    #expect(fixture.files == [first, second])
  }

  @Test(arguments: [nil, FileSlot.left])
  func nothingThatTheFieldsTakeLeavesPasteInvalid(focus: FileSlot?) throws {
    let fixture = CompareFilesFixture()
    if let focus {
      fixture.window.makeFirstResponder(try fixture.field(focus))
    }
    let image = try #require(NSImage(systemSymbolName: "doc", accessibilityDescription: nil))

    let puts: [() -> Void] = [
      { fixture.clipboard.pasteboard.clearContents() },
      {
        fixture.clipboard.pasteboard.clearContents()
        fixture.clipboard.pasteboard.writeObjects([image])
      },
    ]
    for put in puts {
      put()
      #expect(try !canPaste(in: fixture.window))
    }
    #expect(try fixture.clipboard.copies.isEmpty)
  }

  @Test func textWithoutAFocusedFieldAndWithoutAnEmptyOneLeavesPasteInvalid() throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture()
    fixture.controller.fill([.left: try files.file("a.txt"), .right: try files.file("b.txt")])
    fixture.window.makeFirstResponder(nil)
    fixture.clipboard.copy("text\n")

    #expect(try !canPaste(in: fixture.window))

    fixture.window.makeFirstResponder(try fixture.field(.right))
    #expect(try canPaste(in: fixture.window))
  }

  /// Checking whether Paste is valid, as each look at the Edit menu does, reads no text; Paste
  /// reads it once.
  ///
  /// Empty text is known as such only then.
  @Test func checkingPasteReadsTheTypesOfTheClipboardOnly() throws {
    let fixture = CompareFilesFixture()
    let provider = PromisedText("promised\n")
    let item = NSPasteboardItem()
    item.setDataProvider(provider, forTypes: [.string])
    fixture.clipboard.pasteboard.clearContents()
    fixture.clipboard.pasteboard.writeObjects([item])

    for _ in 1...3 {
      #expect(try canPaste(in: fixture.window))
    }
    #expect(provider.requestCount == 0)

    try paste(in: fixture.window)
    #expect(provider.requestCount == 1)
    #expect(try copiedText(in: .left, of: fixture.controller) == "promised\n")

    fixture.clipboard.copy("")
    #expect(try canPaste(in: fixture.window))
    #expect(ClipboardContent.text(on: fixture.clipboard.pasteboard) == nil)
  }

  @Test func formattedTextBecomesPlainText() throws {
    let fixture = CompareFilesFixture()
    let formatted = NSAttributedString(
      string: "bold\nplain\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 20)])
    let rtf = try #require(
      formatted.rtf(
        from: NSRange(location: 0, length: formatted.length), documentAttributes: [:]))
    fixture.clipboard.pasteboard.clearContents()
    fixture.clipboard.pasteboard.setData(rtf, forType: .rtf)

    try paste(in: fixture.window)

    #expect(try copiedText(in: .left, of: fixture.controller) == "bold\nplain\n")
  }

  @Test func laterChangesOfTheClipboardLeaveThePastedTextAsItWas() throws {
    let fixture = CompareFilesFixture()
    fixture.clipboard.copy("first\r\nsecond")

    try paste(in: fixture.window)
    fixture.clipboard.copy("something else\n")

    #expect(try copiedText(in: .left, of: fixture.controller) == "first\r\nsecond")
    #expect(fixture.controller.selection.comparison == nil)
  }

  @Test func mergeFilesAndChangeFilesTakeOnlyFiles() throws {
    let files = try SampleFiles()
    for purpose in [CompareFilesWindowController.Purpose.merge, .change(.diff)] {
      let fixture = CompareFilesFixture(purpose)
      fixture.clipboard.copy("text\n")
      #expect(try !canPaste(in: fixture.window), "\(purpose)")
      #expect(try fixture.field(.left).accessibilityHelp() == "Choose a file, or drop one here")

      let file = try files.file("a.txt")
      fixture.clipboard.copy(files: [file])
      #expect(try canPaste(in: fixture.window))
      try paste(in: fixture.window)
      #expect(fixture.controller.selection[.left] == file)
    }
  }

  @Test func fieldShowsClipboardWithItsLinesAndTimeAndTellsVoiceOver() throws {
    let fixture = CompareFilesFixture()
    fixture.clipboard.copy((1...12).map { "line \($0)" }.joined(separator: "\n"))

    try paste(in: fixture.window)

    let field = try fixture.field(.left)
    let text = try #require(fixture.controller.selection.pastedText(in: .left))
    let time = text.date.formatted(date: .omitted, time: .shortened)
    #expect(text.lineCount == 12)
    #expect(field.accessibilityLabel() == "Left")
    #expect(field.accessibilityValue() as? String == "Clipboard, 12 lines")
    let labels = field.subviews.compactMap { $0 as? NSStackView }.filter { !$0.isHidden }
      .flatMap(\.arrangedSubviews).compactMap { $0 as? NSTextField }.map(\.stringValue)
    #expect(labels == ["Clipboard", "12 lines · \(time)"])
    #expect(field.toolTip == nil)
    #expect(fixture.captions == ["Left", "Right"])

    fixture.clipboard.copy("only line")
    fixture.window.makeFirstResponder(try fixture.field(.right))
    try paste(in: fixture.window)
    #expect(try fixture.field(.right).accessibilityValue() as? String == "Clipboard, 1 line")

    fixture.controller.clear(.left)
    #expect(fixture.announcements.last == "Clipboard removed from Left")
  }

  @Test func linesAreCountedAsThePanesCountThem() {
    let cases: [(String, Int)] = [
      ("", 0), ("a", 1), ("a\n", 1), ("a\nb", 2), ("a\r\nb\r\n", 2), ("a\rb\r", 2), ("\n\n", 2),
      ("a\r\n\nb", 3),
    ]
    for (text, count) in cases {
      #expect(PastedTextCache.lineCount(of: Data(text.utf8)) == count, "\(text.debugDescription)")
    }
  }

  @Test func copyThatNoFieldHoldsGoesAtOnce() throws {
    let fixture = CompareFilesFixture()
    fixture.window.makeFirstResponder(try fixture.field(.left))
    fixture.clipboard.copy("first\n")
    try paste(in: fixture.window)
    let first = try #require(fixture.controller.selection.pastedText(in: .left))

    fixture.clipboard.copy("second\n")
    try paste(in: fixture.window)

    #expect(!FileManager.default.fileExists(atPath: first.url.path(percentEncoded: false)))
    #expect(try fixture.clipboard.copies.count == 1)
    fixture.controller.clear(.left)
    #expect(try fixture.clipboard.copies.isEmpty)
  }

  @Test func copiesGoWithTheSheetUnlessAWindowTookThem() async throws {
    let fixture = try WelcomeFixture()
    fixture.clipboard.copy("left\n")
    fixture.controller.paste(nil)
    try fixture.sheet().cancelOperation(nil)
    #expect(try fixture.clipboard.copies.isEmpty)

    fixture.clipboard.copy("left\n")
    fixture.controller.paste(nil)
    let sheet = try fixture.sheet()
    fixture.clipboard.copy("right\n")
    let window = try #require(sheet.window)
    try paste(in: window)
    let comparison = try #require(sheet.selection.comparison)
    sheet.openComparison(nil)
    await fixture.opener.nextOpening()
    await fixture.nextClose()

    #expect(try fixture.clipboard.copies.count == 2)
    #expect(fixture.opener.opened == [comparison])
    #expect(comparison.pastedTexts.count == 2)
    #expect(fixture.recentComparisons.comparisons.isEmpty)
  }

  @Test func copiesStayWhileTheFilesOpenAndGoIfOpeningFails() async throws {
    let fixture = try WelcomeFixture()
    fixture.opener.failure = SessionLoadingError.comparisonFailed
    fixture.clipboard.copy("left\n")
    fixture.controller.paste(nil)
    let sheet = try fixture.sheet()
    fixture.clipboard.copy("right\n")
    try paste(in: try #require(sheet.window))

    sheet.openComparison(nil)
    await fixture.panels.nextFailure()
    await fixture.opener.nextOpening()
    #expect(try fixture.clipboard.copies.count == 2)

    sheet.cancelOperation(nil)
    #expect(try fixture.clipboard.copies.isEmpty)
  }

  @Test func pasteInTheWelcomeWindowFillsLeftAndPutsTheFocusOnRight() throws {
    let fixture = try WelcomeFixture()
    fixture.clipboard.copy("one\n")

    #expect(try canPaste(in: fixture.window))
    try paste(in: fixture.window)

    let sheet = try fixture.sheet()
    #expect(sheet.purpose == .compare)
    #expect(try copiedText(in: .left, of: sheet) == "one\n")
    #expect(sheet.selection[.right] == nil)
    #expect(sheet.window?.firstResponder === sheet.fields[.right])
  }

  @Test func filesPastedInTheWelcomeWindowFillTheSheetAsFromTheDock() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let urls = [try files.file("a.txt"), try files.file("o.txt"), try files.file("b.txt")]

    fixture.clipboard.copy(files: Array(urls.prefix(1)))
    try paste(in: fixture.window)
    #expect(try fixture.sheet().purpose == .compare)
    #expect(try fixture.files() == [urls[0], nil])
    try fixture.sheet().cancelOperation(nil)

    fixture.clipboard.copy(files: urls)
    try paste(in: fixture.window)
    #expect(try fixture.sheet().purpose == .merge)
    #expect(try fixture.files() == urls)
  }

  /// While another sheet hangs on the welcome window, Paste is invalid; sent anyway, it reads the
  /// clipboard at once, and the sheet that waits shows what was there then.
  @Test func pasteWhileAnotherSheetHangsReadsTheClipboardAtOnce() async throws {
    let fixture = try WelcomeFixture()
    fixture.controller.showWindow(nil)
    let other = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled],
      backing: .buffered, defer: false)
    other.isReleasedWhenClosed = false
    fixture.window.beginSheet(other) { _ in }
    fixture.clipboard.copy("then\n")
    #expect(try !canPaste(in: fixture.window))

    fixture.controller.paste(nil)
    fixture.clipboard.copy("later\n")
    #expect(fixture.controller.filesSheet == nil)
    fixture.window.endSheet(other)
    var turns = 0
    while fixture.controller.filesSheet == nil && turns < 100 {
      await Task.yield()
      turns += 1
    }

    #expect(try copiedText(in: .left, of: fixture.sheet()) == "then\n")
  }

  @Test func welcomeWindowRefusesWhatNoSheetTakes() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let puts: [() throws -> Void] = [
      { fixture.clipboard.pasteboard.clearContents() },
      { fixture.clipboard.copy(files: try (1...4).map { try files.file("\($0).txt") }) },
    ]
    for put in puts {
      try put()
      #expect(try !canPaste(in: fixture.window))
    }
  }

  /// Text copied, ⌘V in the welcome window, other text copied, ⌘V, ↩; and in the sheet, ⌘V,
  /// ⇥, ⌘V, ↩: the keyboard alone compares two texts.
  @Test func keyboardAloneComparesTwoTexts() async throws {
    let fixture = try WelcomeFixture()
    fixture.clipboard.copy("first\n")
    try paste(in: fixture.window)
    let sheet = try fixture.sheet()
    let sheetWindow = try #require(sheet.window)
    fixture.clipboard.copy("second\n")
    try paste(in: sheetWindow)
    #expect(try copiedText(in: .left, of: sheet) == "first\n")
    #expect(try copiedText(in: .right, of: sheet) == "second\n")
    #expect(sheet.openButton.isEnabled)

    let inSheet = CompareFilesFixture()
    inSheet.controller.focusFirstEmptyField()
    inSheet.clipboard.copy("first\n")
    try paste(in: inSheet.window)
    inSheet.window.selectNextKeyView(nil)
    inSheet.clipboard.copy("second\n")
    try paste(in: inSheet.window)
    #expect(try copiedText(in: .left, of: inSheet.controller) == "first\n")
    #expect(try copiedText(in: .right, of: inSheet.controller) == "second\n")
    #expect(inSheet.controller.openButton.keyEquivalent == "\r")
    inSheet.controller.openButton.performClick(nil)
    await inSheet.opener.nextOpening()
    let opened = try #require(inSheet.opener.opened.first)
    #expect(opened.pastedTexts.count == 2)
  }
}

/// Text on the clipboard that is written only once it is asked for, as an app that promises a
/// large text does; it counts how often it was asked.
private final class PromisedText: NSObject, NSPasteboardItemDataProvider, Sendable {
  private let text: String
  private let requests = Mutex(0)

  init(_ text: String) {
    self.text = text
  }

  /// How often the text was asked for.
  var requestCount: Int {
    requests.withLock { $0 }
  }

  func pasteboard(
    _ pasteboard: NSPasteboard?, item: NSPasteboardItem,
    provideDataForType type: NSPasteboard.PasteboardType
  ) {
    requests.withLock { $0 += 1 }
    item.setString(text, forType: type)
  }
}
