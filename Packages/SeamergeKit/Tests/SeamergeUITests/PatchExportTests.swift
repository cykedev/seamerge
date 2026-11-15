import AppKit
import GitSupport
import MergeModel
import Testing

@testable import SeamergeUI

/// Export as Patch and Copy as Patch: the patch counts every byte whatever the window shows,
/// leads from left to right, holds every changed file of a window of several, and the commands
/// are valid only where they have an effect.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct PatchExportTests {
  static let old = Data("struct Point {\n    var x: Int\n  var y: Int\n}\r\n".utf8)
  static let new = Data("struct Point {\n  var x: Int\n  var y: Int\n  var z: Int\n}\r\n".utf8)

  @Test func patchOfAWindowThatIgnoresWhitespaceMakesTheNewFileByteForByte() async throws {
    let rules = [IgnoreRule(name: "Types", pattern: "Int")]
    let session = try await Session.diff(
      old: SourceFile(bytes: Self.old, label: "Point.swift"),
      new: SourceFile(bytes: Self.new, label: "Point.swift"), mode: .ignoreWhitespaceAmount,
      ignoring: rules)
    let prompts = PromptRecorder()
    let folder = try SampleCollections.folder()
    prompts.patchDestination = folder.appending(path: "Point.patch")
    let controller = try Windows.controller(
      for: session, context: Self.context(path: "Sources/Point.swift"), prompts: prompts)

    #expect(await controller.copyPatchToPasteboard())
    #expect(await controller.exportPatchChoosingPlace())

    let copied = try #require(controller.pasteboard.string(forType: .string))
    let exported = try Data(contentsOf: folder.appending(path: "Point.patch"))
    #expect(Data(copied.utf8) == exported)
    for tool in [PatchApplication.Tool.git, .patch] {
      let applied = try await PatchApplication.apply(
        exported, to: ["Sources/Point.swift": Self.old], with: tool)
      #expect(applied == ["Sources/Point.swift": Self.new], "\(tool)")
    }
    #expect(prompts.questions == ["where to export Point.swift.patch"])
    #expect(prompts.patchFileCounts == [nil])
  }

  @Test func swapSidesTurnsThePatchRound() async throws {
    let session = try await Session.diff(
      old: SourceFile(bytes: Self.old, label: "Point.swift"),
      new: SourceFile(bytes: Self.new, label: "Point.swift"))
    let controller = try Windows.controller(
      for: session, context: Self.context(path: "Point.swift"))
    #expect(await controller.copyPatchToPasteboard())
    let forward = try #require(controller.pasteboard.string(forType: .string))

    controller.swapSides(nil)
    #expect(await controller.copyPatchToPasteboard())
    let backward = try #require(controller.pasteboard.string(forType: .string))

    #expect(forward.contains("+  var z: Int\n"))
    #expect(backward.contains("-  var z: Int\n"))
    let applied = try await PatchApplication.apply(
      Data(backward.utf8), to: ["Point.swift": Self.new], with: .git)
    #expect(applied == ["Point.swift": Self.old])
  }

  @Test func sidesWithoutAPathAreNamedAsTheirHeadersNameThem() async throws {
    let session = try await Session.diff(
      old: SourceFile(bytes: Data("a\n".utf8), label: "draft.txt"),
      new: SourceFile(bytes: Data("b\n".utf8), label: "final.txt"))
    let controller = try Windows.controller(for: session)

    #expect(await controller.copyPatchToPasteboard())

    let patch = try #require(controller.pasteboard.string(forType: .string))
    #expect(patch.hasPrefix("--- draft.txt\n+++ final.txt\n@@ -1 +1 @@\n"))
    #expect(controller.suggestedPatchName == "final.txt.patch")
  }

  @Test func newFileOfGitDifftoolLeadsFromDevNull() async throws {
    let session = try await Session.diff(
      old: SourceFile(bytes: Data(), label: "Notes.md", url: URL(filePath: "/dev/null")),
      new: SourceFile(bytes: Data("# Notes\n".utf8), label: "Notes.md"))
    let controller = try Windows.controller(for: session, context: Self.context(path: "Notes.md"))

    #expect(await controller.copyPatchToPasteboard())

    let patch = try #require(controller.pasteboard.string(forType: .string))
    #expect(patch.contains("new file mode 100644\n--- /dev/null\n+++ b/Notes.md\n"))
  }

  @Test func filesOfAnotherEncodingAreCopiedInTheirCharactersAndExportedInTheirBytes() async throws
  {
    let old = Data("Gr".utf8) + Data([0xF6, 0xDF]) + Data("e\n".utf8)
    let new = Data("gr".utf8) + Data([0xF6, 0xDF]) + Data("e\n".utf8)
    let session = try await Session.diff(
      old: SourceFile(bytes: old, label: "size.txt"),
      new: SourceFile(bytes: new, label: "size.txt"))
    let prompts = PromptRecorder()
    let folder = try SampleCollections.folder()
    prompts.patchDestination = folder.appending(path: "size.patch")
    let controller = try Windows.controller(
      for: session, context: Self.context(path: "size.txt"), prompts: prompts)

    #expect(await controller.copyPatchToPasteboard())
    #expect(await controller.exportPatchChoosingPlace())

    let copied = try #require(controller.pasteboard.string(forType: .string))
    #expect(copied.hasSuffix("-Größe\n+größe\n"))
    let exported = try Data(contentsOf: folder.appending(path: "size.patch"))
    #expect(
      exported.suffix(old.count + new.count + 2) == Data("-".utf8) + old + Data("+".utf8) + new)
  }

  @Test func commandsAreValidOnlyInAComparisonWithBytesThatDiffer() async throws {
    let changed = try Windows.controller(for: try await SampleDiffs.greeting())
    let same = try Windows.controller(
      for: try await SampleDiffs.diff(old: "a\n", new: "a\n"))
    let whitespaceOnly = try Windows.controller(
      for: try await SampleDiffs.diff(old: "a  b\n", new: "a b\n", mode: .ignoreWhitespaceAmount))
    let merge = try Windows.controller(for: try await SampleMerges.helloWorld())
    let unavailableComparison = SampleDiffs.unavailable(isBinary: true)
    let unavailable = try Windows.controller(
      for: try await unavailableComparison.emptySession(), unavailable: unavailableComparison)
    let wide = try Windows.controller(
      for: try await Session.diff(
        old: SourceFile(bytes: Data("a\n".utf8), label: "wide.txt"),
        new: SourceFile(bytes: Data([0xFF, 0xFE, 0x62, 0x00, 0x0A, 0x00]), label: "wide.txt")))

    #expect(whitespaceOnly.presentation.changes.blocks.isEmpty)
    for command in [SessionCommand.copyPatch, .exportPatch] {
      #expect(changed.canPerform(command))
      #expect(whitespaceOnly.canPerform(command), "Every byte counts")
      #expect(!same.canPerform(command))
      #expect(!merge.canPerform(command))
      #expect(!unavailable.canPerform(command))
      #expect(!wide.canPerform(command), "A file in UTF-16 alone would only say that it differs")
      let item = NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
      #expect(changed.validateUserInterfaceItem(item))
      #expect(!merge.validateUserInterfaceItem(item))
      #expect(Keys.of(command, in: .diff) == nil)
      #expect(command.help == "Records every byte, whatever the comparison mode")
    }
    #expect(SessionCommand.groups(in: .file).contains([.exportPatch]))
    #expect(SessionCommand.groups(in: .edit).contains([.copyBlock, .copyPatch]))
  }

  @Test func patchOfACollectionHoldsEveryChangedFileInTheOrderOfTheListWhateverTheFilter()
    async throws
  {
    let folder = try SampleCollections.folder()
    let files = try SampleCollections.commit(in: folder)
    let collection = FileCollection(files: files)
    let prompts = PromptRecorder()
    prompts.patchDestination = folder.appending(path: "commit.patch")
    let controller = try await Windows.controller(for: collection, prompts: prompts)
    let fileList = try #require(controller.collectionLayout?.fileList)
    fileList.filterField.stringValue = "README"
    controller.fileList(fileList, didChangeFilter: "README")
    try #require(fileList.files.map(\.path) == ["README.md"])

    #expect(controller.canPerform(.exportPatch))
    #expect(await controller.exportPatchChoosingPlace())

    let patch = try Data(contentsOf: folder.appending(path: "commit.patch"))
    let headers = String(decoding: patch, as: UTF8.self).split(separator: "\n")
      .filter { $0.hasPrefix("diff --git a/") }
      .map { $0.dropFirst("diff --git a/".count).split(separator: " ").first.map(String.init) }
    #expect(headers == files.map(\.path))
    let old = try Self.sides(of: files, new: false)
    let new = try Self.sides(of: files, new: true)
    #expect(try await PatchApplication.apply(patch, to: old, with: .git) == new)
    #expect(try await PatchApplication.apply(patch, to: old, with: .patch) == new)
    #expect(prompts.questions == ["where to export changes.patch"])
    #expect(prompts.patchFileCounts == [5])

    controller.swapSides(nil)
    #expect(await controller.copyPatchToPasteboard())
    let backward = Data(try #require(controller.pasteboard.string(forType: .string)).utf8)
    #expect(try await PatchApplication.apply(backward, to: new, with: .git) == old)
  }

  @Test func patchOfTwoFoldersMakesTheRightFolderOfTheLeftOne() async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    let collection = await FileCollection.compared(folders)
    let prompts = PromptRecorder()
    prompts.patchDestination = folders.folder.appending(path: "folders.patch")
    let controller = try await Windows.controller(for: collection, prompts: prompts)

    #expect(await controller.exportPatchChoosingPlace())

    let patch = try Data(contentsOf: folders.folder.appending(path: "folders.patch"))
    let compared = collection.files.filter(\.belongsToPatch)
    let left = try Self.sides(of: compared, new: false)
    let right = try Self.sides(of: compared, new: true)
    #expect(try await PatchApplication.apply(patch, to: left, with: .git) == right)
    #expect(prompts.questions == ["where to export Orders 1.0-Orders 1.1.patch"])
    #expect(prompts.patchFileCounts == [compared.count])
    #expect(!compared.contains { $0.path == "LICENSE" }, "Identical files are left out")
  }

  @Test func collectionOfFilesThatCannotBeShownWritesOnlyThatTheyDiffer() async throws {
    let folder = try SampleCollections.folder()
    let image = try SampleCollections.file("logo.png", old: "\u{0}old", new: "\u{0}new", in: folder)
    let collection = FileCollection(files: [image])
    let controller = try await Windows.controller(for: collection)
    try #require(controller.unavailable != nil)

    #expect(controller.canPerform(.copyPatch))
    #expect(await controller.copyPatchToPasteboard())

    #expect(
      controller.pasteboard.string(forType: .string) == """
        diff --git a/logo.png b/logo.png
        Binary files a/logo.png and b/logo.png differ

        """)
  }

  @Test func foldersWithIdenticalFilesOnlyHaveNoPatch() async throws {
    let folders = try SampleFolders()
    try folders.write("same.txt", left: "a\n", right: "a\n")
    let collection = await FileCollection.compared(folders)
    try #require(collection.files.map(\.change) == [.identical])
    let controller = try await Windows.controller(for: collection)

    #expect(!controller.canPerform(.copyPatch))
    #expect(!controller.canPerform(.exportPatch))
  }

  @Test func copyingAndExportingSayToVoiceOverWhatHappened() async throws {
    let prompts = PromptRecorder()
    let folder = try SampleCollections.folder()
    prompts.patchDestination = folder.appending(path: "greeting.patch")
    let single = try Windows.controller(for: try await SampleDiffs.greeting(), prompts: prompts)
    let collection = try await Windows.controller(
      for: FileCollection(files: try SampleCollections.commit(in: folder)))
    var heard: [String] = []
    for controller in [single, collection] {
      controller.presentation.announce = { heard.append($0) }
    }

    #expect(await single.copyPatchToPasteboard())
    #expect(await single.exportPatchChoosingPlace())
    #expect(await collection.copyPatchToPasteboard())

    #expect(
      heard == ["Copied the patch", "Exported greeting.patch", "Copied the patch of 5 files"])
  }

  @Test func failuresSayWhatWentWrongAndWhatToDoNext() {
    let tooLarge = PatchError(.outOfMemory)
    let failed = PatchError(.comparisonFailed)
    let unwritable = PatchError.writingFailed(reason: "The volume is read only.")

    #expect(tooLarge.errorDescription == "The files are too large to compare.")
    #expect(tooLarge.recoverySuggestion == "Quit other apps to free memory, then try again.")
    #expect(failed.errorDescription == "Seamerge couldn’t compare the files.")
    #expect(
      failed.recoverySuggestion
        == "Try again. If it fails again, use another tool for these files.")
    #expect(unwritable.errorDescription == "The volume is read only.")
    #expect(unwritable.recoverySuggestion == "Choose another folder, then export again.")
  }

  @Test func failedExportShowsASheetWithTheReason() async throws {
    let prompts = PromptRecorder()
    prompts.patchDestination = URL(filePath: "/nonexistent-\(UUID().uuidString)/greeting.patch")
    let controller = try Windows.controller(
      for: try await SampleDiffs.greeting(), prompts: prompts)

    #expect(await !controller.exportPatchChoosingPlace())

    #expect(prompts.questions.count == 2)
    #expect(prompts.questions.last?.hasPrefix("failed patch greeting.patch: ") == true)
  }

  @Test func cancelledChoiceWritesNothing() async throws {
    let prompts = PromptRecorder()
    let controller = try Windows.controller(
      for: try await SampleDiffs.greeting(), prompts: prompts)

    #expect(await !controller.exportPatchChoosingPlace())

    #expect(prompts.questions == ["where to export Greeting.swift.patch"])
  }

  private static func context(path: String) -> SessionContext {
    SessionContext(difftool: DifftoolContext(path: path))
  }

  /// The older or newer side of each of `files` that exists, by path.
  private static func sides(of files: [CollectedFile], new: Bool) throws -> [String: Data] {
    try files.reduce(into: [:]) { sides, file in
      let url = new ? file.new.url : file.old.url
      guard FileOrigin(url: url) != .missing else { return }
      sides[file.path] = try Data(contentsOf: url)
    }
  }
}
