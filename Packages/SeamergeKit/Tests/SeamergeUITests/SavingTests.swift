import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// Saving the result and closing the window: what lands in the file, and what Git hears.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SavingTests {
  /// A window of `scenario` whose result goes to a file of its own in a temporary folder, which
  /// holds `content` until the window saves; the folder is removed when the test ends.
  @MainActor
  private final class Fixture {
    let controller: SessionWindowController
    let prompts = PromptRecorder()
    let folder: URL
    let resultURL: URL
    private(set) var outcomes: [SessionOutcome] = []

    init(
      _ scenario: String, options: ComparisonOptions = .init(mode: .windowDefault),
      content: Data = Data("<<<<<<< conflict\n".utf8),
      waitingCaller: WaitingCaller? = .git
    ) async throws {
      let scenario = try #require(Scenario.merges.first { $0.name == scenario })
      let (session, gitContext) = try await scenario.load(options: options)
      folder = FileManager.default.temporaryDirectory.appending(
        path: "SavingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      resultURL = folder.appending(path: scenario.file)
      try content.write(to: resultURL)
      let context = SessionContext(
        resultURL: resultURL, git: gitContext.git, waitingCaller: waitingCaller)
      controller = try Windows.controller(for: session, context: context, prompts: prompts)
      controller.onFinish = { [weak self] in self?.outcomes.append($0) }
    }

    isolated deinit {
      do {
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try FileManager.default.removeItem(at: folder)
      } catch {
        Issue.record("Could not remove \(folder.path): \(error)")
      }
    }

    var written: Data {
      get throws { try Data(contentsOf: resultURL) }
    }

    var outcomeNames: [String] {
      outcomes.map { if case .saved = $0 { "saved" } else { "cancelled" } }
    }
  }

  private static func lines(_ fifth: String) -> String {
    (1...10).map { $0 == 5 ? fifth : "line \($0)" }.map { $0 + "\n" }.joined()
  }

  @Test func mergeSolvedFromTheKeyboardIsSavedByDoneAndReportedAsSaved() async throws {
    let fixture = try await Fixture("merge")
    let controller = fixture.controller
    #expect(controller.presentation.navigation.openConflictCount == 1)

    try press("1", in: controller)
    #expect(controller.presentation.navigation.openConflictCount == 0)
    #expect(Keys.of(.saveAndClose, in: .merge) == Keys("\r", .command))
    #expect(await controller.saveAndCloseWindow())

    #expect(try fixture.written == Data(Self.lines("line 5 from feature").utf8))
    #expect(fixture.outcomeNames == ["saved"])
    #expect(fixture.prompts.questions.isEmpty)
    #expect(controller.window?.isVisible != true)
  }

  @Test func savingWithMarkersWritesBThenBaseThenAAndReportsSaved() async throws {
    let fixture = try await Fixture("merge")
    fixture.prompts.openConflictsChoice = .saveWithMarkers
    let labels = fixture.controller.conflictLabels

    #expect(await fixture.controller.saveAndCloseWindow())

    let expected = Self.lines("line 5").replacingOccurrences(
      of: "line 5\n",
      with: """
        <<<<<<< \(labels.b)
        line 5 from main
        ||||||| \(labels.base)
        line 5
        =======
        line 5 from feature
        >>>>>>> \(labels.a)

        """)
    #expect(try fixture.written == Data(expected.utf8))
    #expect(labels.b == "main" && labels.a == "feature")
    #expect(fixture.prompts.questions == ["save with 1 open conflicts, Git"])
    #expect(fixture.outcomeNames == ["saved"])
  }

  @Test func goingToTheNextConflictInsteadSavesNothing() async throws {
    let fixture = try await Fixture("merge")
    fixture.prompts.openConflictsChoice = .goToNextConflict
    let before = try fixture.written
    fixture.controller.presentation.setCurrentBlock(nil)

    #expect(await !fixture.controller.save())

    #expect(try fixture.written == before)
    let conflict = fixture.controller.presentation.navigation.firstOpenConflict
    #expect(fixture.controller.presentation.currentBlock == conflict)
    #expect(fixture.outcomeNames.isEmpty)
  }

  @Test func closingWithoutSavingReportsCancelledAndLeavesTheFileAsItWas() async throws {
    let fixture = try await Fixture("merge")
    fixture.prompts.unsavedChangesChoice = .discard
    let before = try fixture.written
    fixture.controller.resolveOpenConflicts(with: [.b])

    #expect(await fixture.controller.closeAskingFirst())

    #expect(try fixture.written == before)
    #expect(fixture.outcomeNames == ["cancelled"])
    #expect(fixture.prompts.questions == ["close story.txt, 0 open, Git"])
  }

  @Test func closingAsksWithTheOpenConflictsAndCancelKeepsTheWindowOpen() async throws {
    let fixture = try await Fixture("merge")

    #expect(await !fixture.controller.closeAskingFirst())

    #expect(fixture.prompts.questions == ["close story.txt, 1 open, Git"])
    #expect(fixture.outcomeNames.isEmpty)
  }

  @Test func closingWithSaveWritesFirstAndReportsSaved() async throws {
    let fixture = try await Fixture("merge")
    fixture.prompts.unsavedChangesChoice = .save
    fixture.controller.resolveOpenConflicts(with: [.b])

    #expect(await fixture.controller.closeAskingFirst())

    #expect(try fixture.written == Data(Self.lines("line 5 from main").utf8))
    #expect(fixture.outcomeNames == ["saved"])
  }

  @Test func editedWindowThatClosesWithoutAskingReportsCancelled() async throws {
    let fixture = try await Fixture("merge")
    fixture.controller.resolveOpenConflicts(with: [.b])
    #expect(await fixture.controller.save())
    fixture.controller.presentation.setCurrentBlock(0)
    fixture.controller.perform(.useA)
    #expect(fixture.controller.window?.isDocumentEdited == true)

    fixture.controller.closeAsTheAppQuits()

    #expect(fixture.outcomeNames == ["cancelled"])
  }

  @Test func closingASavedResultAsksNothingAndReportsSavedOnce() async throws {
    let fixture = try await Fixture("merge")
    fixture.controller.resolveOpenConflicts(with: [.b])
    #expect(await fixture.controller.save())
    let window = try #require(fixture.controller.window)

    window.performClose(nil)
    window.close()

    #expect(fixture.prompts.questions.isEmpty)
    #expect(fixture.outcomeNames == ["saved"])
  }

  @Test func editedPointFollowsTheSavedStateThroughUndo() async throws {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let session = try await SampleMerges.helloWorld()
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "SavingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    let url = folder.appending(path: "HelloWorld.java")
    let controller = try Windows.controller(
      for: session, context: SessionContext(resultURL: url), undoManager: undoManager)
    let window = try #require(controller.window)
    #expect(window.isDocumentEdited)

    controller.presentation.setCurrentBlock(controller.presentation.navigation.firstOpenConflict)
    undoManager.beginUndoGrouping()
    controller.perform(.useB)
    undoManager.endUndoGrouping()
    #expect(await controller.save())
    #expect(!window.isDocumentEdited)

    undoManager.undo()
    #expect(window.isDocumentEdited)
    undoManager.redo()
    #expect(!window.isDocumentEdited)
  }

  @Test func leavingUnresolvedAsksOnlyWhenDecisionsWouldBeLost() async throws {
    let untouched = try await Fixture("merge")
    #expect(await untouched.controller.leaveUnresolvedAskingFirst())
    #expect(untouched.prompts.questions.isEmpty)
    #expect(untouched.outcomeNames == ["cancelled"])

    let decided = try await Fixture("merge")
    decided.controller.resolveOpenConflicts(with: [.a])
    #expect(await decided.controller.save())
    #expect(await !decided.controller.leaveUnresolvedAskingFirst())
    #expect(decided.prompts.questions == ["leave story.txt unresolved, 1 decisions, Git"])
    #expect(decided.outcomeNames.isEmpty)
    decided.prompts.leavesUnresolvedAnyway = true
    #expect(await decided.controller.leaveUnresolvedAskingFirst())
    #expect(decided.outcomeNames == ["cancelled"])
  }

  @Test func mergeByHandOfFilesInARepositoryNamesGitNowhere() async throws {
    let fixture = try await Fixture("merge", waitingCaller: .commandLine)
    let controller = fixture.controller
    #expect(controller.context.git != nil)

    #expect(await !controller.save())
    #expect(await !controller.closeAskingFirst())
    controller.resolveOpenConflicts(with: [.a])
    #expect(await !controller.leaveUnresolvedAskingFirst())
    #expect(await controller.save())

    #expect(
      fixture.prompts.questions == [
        "save with 1 open conflicts", "close story.txt, 1 open, command line",
        "leave story.txt unresolved, 1 decisions",
      ])
    #expect(controller.layout.resultHeader?.callerIsGit == false)
    #expect(SessionCommand.leaveUnresolved.help?.contains("Git") == false)
    // Saved, the decisions stay in the file, which no one puts back.
    #expect(await controller.leaveUnresolvedAskingFirst())
    #expect(fixture.prompts.questions.count == 3)
    #expect(fixture.outcomeNames == ["cancelled"])
  }

  @Test func otherAppThatWritesTheResultWhileASheetOfSavingIsOpenIsAskedAbout() async throws {
    let fixture = try await Fixture("merge")
    fixture.prompts.openConflictsChoice = .saveWithMarkers
    fixture.prompts.whileAskingToSaveWithOpenConflicts = {
      do {
        try Data("edited elsewhere\n".utf8).write(to: fixture.resultURL)
      } catch {
        Issue.record(error)
      }
    }

    #expect(await fixture.controller.save())

    #expect(fixture.prompts.questions.contains("reload changed story.txt"))
    #expect(try fixture.written != Data("edited elsewhere\n".utf8))
    #expect(fixture.controller.window?.isDocumentEdited == false)
  }

  @Test func reloadingWhatAnotherAppWroteBeforeDoneKeepsTheWindowOpenToShowIt() async throws {
    let fixture = try await Fixture("merge")
    let controller = fixture.controller
    controller.resolveOpenConflicts(with: [.b])
    let markers = "<<<<<<< ours\nmine\n=======\ntheirs\n>>>>>>> theirs\n"
    try Data(markers.utf8).write(to: fixture.resultURL)
    fixture.prompts.reloadsChangedResult = true

    #expect(await !controller.saveAndCloseWindow())

    #expect(fixture.prompts.questions == ["reload changed story.txt"])
    #expect(fixture.outcomeNames.isEmpty)
    #expect(!controller.hasFinished)
    #expect(controller.presentation.result?.text == markers)
    #expect(try fixture.written == Data(markers.utf8))
    #expect(controller.window?.isDocumentEdited == false)
  }

  @Test func otherAppThatWritesTheResultWhileUTF8IsOfferedIsAskedAbout() async throws {
    let fixture = try await Fixture("merge")
    let controller = fixture.controller
    controller.resolveOpenConflicts(with: [.b])
    controller.choose(.encoding(.isoLatin1))
    try controller.type("€ ", over: 0..<0, with: .insertText)
    fixture.prompts.savesAsUTF8 = true
    fixture.prompts.whileOfferingUTF8 = {
      do {
        try Data("edited elsewhere\n".utf8).write(to: fixture.resultURL)
      } catch {
        Issue.record(error)
      }
    }

    #expect(await controller.save())

    #expect(
      fixture.prompts.questions == [
        "save story.txt as UTF-8 instead of ISO 8859-1", "reload changed story.txt",
      ])
    #expect(String(decoding: try fixture.written, as: UTF8.self).hasPrefix("€ "))
  }

  @Test func leavingUnresolvedNeedsSomeoneWhoWaits() async throws {
    let fixture = try await Fixture("merge", waitingCaller: nil)

    #expect(!fixture.controller.canPerform(.leaveUnresolved))
    #expect(fixture.controller.canPerform(.save))
  }

  @Test func crlfIsWrittenWithCRLFThroughout() async throws {
    let fixture = try await Fixture("crlf")
    fixture.controller.resolveOpenConflicts(with: [.a, .b])

    #expect(await fixture.controller.save())

    let text = String(decoding: try fixture.written, as: UTF8.self)
    #expect(text.contains("line 5 from feature\r\nline 5 from main\r\n"))
    #expect(text.components(separatedBy: "\r\n").count == 12)
    #expect(!text.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
  }

  @Test func utf16IsWrittenInUTF16WithItsByteOrderMark() async throws {
    let fixture = try await Fixture("utf16")
    fixture.controller.resolveOpenConflicts(with: [.b])

    #expect(await fixture.controller.save())

    let bytes = try fixture.written
    #expect(bytes.prefix(2) == Data([0xFF, 0xFE]))
    let text = String(data: bytes.dropFirst(2), encoding: .utf16LittleEndian)
    #expect(text?.contains("Grüße from main\n") == true)
  }

  @Test func whitespaceWhileIgnoringItsChangesHasNoOpenConflictAndTakesTheIndentationOfB()
    async throws
  {
    let fixture = try await Fixture("whitespace", options: .init(mode: .ignoreWhitespaceAmount))
    let controller = fixture.controller
    #expect(controller.presentation.navigation.openConflictCount == 0)

    #expect(await controller.saveAndCloseWindow())

    let b = "func run() {\n  let a = 1  \n  let b = 2\n    return a + b\n}\n"
    #expect(try fixture.written == Data(b.utf8))
    #expect(fixture.outcomeNames == ["saved"])
  }

  @Test func resultWithoutAFileAsksWhereOnceAndThenSavesThere() async throws {
    let session = try await SampleMerges.helloWorld()
    let prompts = PromptRecorder()
    let controller = try Windows.controller(for: session, prompts: prompts)
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "SavingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    prompts.destination = folder.appending(path: "Merged.java")
    prompts.openConflictsChoice = .saveWithMarkers
    #expect(controller.window?.isDocumentEdited == false)

    #expect(await controller.save())
    controller.resolveOpenConflicts(with: [.a])
    #expect(await controller.save())

    #expect(prompts.questions.filter { $0.hasPrefix("where") }.count == 1)
    #expect(controller.window?.representedURL == prompts.destination)
    #expect(controller.fileWatchers.map(\.url) == [prompts.destination].compactMap(\.self))
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Merged.java").path))
  }

  @Test func encodingThatCannotHoldTheResultOffersUTF8() async throws {
    let session = try await Session.merge(
      base: SourceFile(bytes: Data("price\n".utf8), label: "prices.txt"),
      a: SourceFile(bytes: Data("price 5 €\n".utf8), label: "prices.txt"),
      b: SourceFile(bytes: Data("price\n".utf8), label: "prices.txt"))
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "SavingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    let url = folder.appending(path: "prices.txt")
    let prompts = PromptRecorder()
    let controller = try Windows.controller(
      for: session, context: SessionContext(resultURL: url), prompts: prompts)
    controller.choose(.encoding(.isoLatin1))

    #expect(await !controller.save())
    #expect(!FileManager.default.fileExists(atPath: url.path))
    prompts.savesAsUTF8 = true
    #expect(await controller.save())

    #expect(try Data(contentsOf: url) == Data("price 5 €\n".utf8))
    #expect(controller.saving?.format.encoding == .utf8)
    #expect(controller.layout.resultHeader?.format.encoding == .utf8)
    #expect(
      prompts.questions == [
        "save prices.txt as UTF-8 instead of ISO 8859-1",
        "save prices.txt as UTF-8 instead of ISO 8859-1",
      ])
  }

  @Test func failureToWriteKeepsTheWindowAndItsWorkAndSaysSo() async throws {
    let fixture = try await Fixture("merge")
    fixture.controller.resolveOpenConflicts(with: [.b])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: fixture.folder.path)
    let before = try fixture.written

    #expect(await !fixture.controller.saveAndCloseWindow())

    #expect(try fixture.written == before)
    #expect(fixture.prompts.questions == ["failed saving story.txt"])
    #expect(fixture.outcomeNames.isEmpty)
    #expect(fixture.controller.window?.isDocumentEdited == true)
    #expect(fixture.controller.presentation.navigation.openConflictCount == 0)
  }

  @Test func chosenLineEndingIsWrittenAndUndoBringsBackTheFormerOne() async throws {
    let fixture = try await Fixture("merge")
    let controller = fixture.controller
    controller.resolveOpenConflicts(with: [.b])
    let item = ResultFormatChoice.lineEnding(.crlf).menuItem()
    let lf = ResultFormatChoice.lineEnding(.lf).menuItem()
    #expect(controller.validateUserInterfaceItem(lf) && lf.state == .on)

    controller.chooseResultFormat(item)
    controller.endEvent()
    #expect(controller.validateUserInterfaceItem(item) && item.state == .on)
    #expect(controller.layout.resultHeader?.format.lineEnding == .crlf)
    #expect(await controller.save())
    let crlf = Self.lines("line 5 from main").replacingOccurrences(of: "\n", with: "\r\n")
    #expect(try fixture.written == Data(crlf.utf8))

    controller.sessionUndoManager.undo()
    #expect(controller.saving?.format.lineEnding == .lf)
    #expect(controller.layout.resultHeader?.format.lineEnding == .lf)
  }

  @Test func namesInTheMarkersStandOnOneLine() async throws {
    let session = try await Session.merge(
      base: SourceFile(bytes: Data("x\n".utf8), label: "base\nfile"),
      a: SourceFile(bytes: Data("a\n".utf8), label: "a\tfile"),
      b: SourceFile(bytes: Data("b\n".utf8), label: "b\r\nfile"))
    let controller = try Windows.controller(for: session)

    let labels = controller.conflictLabels

    #expect(labels == ConflictLabels(a: "a file", base: "base file", b: "b  file"))
    let document = try #require(controller.presentation.result?.document)
    let text = document.exportText(
      of: try #require(controller.presentation.result?.text), labels: labels)
    #expect(text.split(separator: "\n").count == 7)
  }

  @Test func mixedLineEndingsOfBAreUnifiedAndTheHeaderSaysSo() async throws {
    let session = try await Session.merge(
      base: SourceFile(bytes: Data("1\n2\n3\n".utf8), label: "base"),
      a: SourceFile(bytes: Data("1\n2\n3\n".utf8), label: "a"),
      b: SourceFile(bytes: Data("1\r\n2\r\n3\n".utf8), label: "b"))
    let controller = try Windows.controller(for: session)

    let header = try #require(controller.layout.resultHeader)

    #expect(header.bWithMixedLineEndings == "b")
    #expect(header.format.lineEnding == .crlf)
  }
}
