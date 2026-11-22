import AppKit
import GitSupport
import MergeModel
import Testing

@testable import FolderCompare
@testable import SeamergeUI

/// `git difftool` against the working copy in a repository of its own: what saving writes, what
/// Git hears when the window closes, and that only the working copy is ever written.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct DifftoolSavingTests {
  /// The window of `comparison` as the app opens it for the helper that Git started, whose
  /// outcome goes back to Git as the helper's exit status.
  private static func window(
    for comparison: DifftoolRun.Comparison, of run: DifftoolRun, prompts: PromptRecorder
  ) async throws -> SessionWindowController {
    let difftool = DifftoolContext.detect(
      path: comparison.path, leftFile: comparison.left, rightFile: comparison.right,
      workingDirectory: comparison.workingDirectory, environment: [:])
    let session = try await Session.loadDiff(
      old: SessionFile(url: comparison.left, label: comparison.path),
      new: SessionFile(url: comparison.right, label: comparison.path), mode: .windowDefault)
    let controller = try Windows.controller(
      for: session, context: SessionContext(difftool: difftool, waitingCaller: .git),
      prompts: prompts)
    controller.onFinish = { outcome in
      Task { await run.reply(outcome == .saved ? 0 : 1) }
    }
    return controller
  }

  /// Copies every change of `controller` to the working copy on the right and waits for it.
  private static func copyAllToTheWorkingCopy(in controller: SessionWindowController) async {
    #expect(controller.canPerform(.copyAllChangesToRight))
    #expect(!controller.canPerform(.copyAllChangesToLeft))
    controller.copyAllChangesToRight(nil)
    await controller.copying?.value
  }

  @Test func savedCopyIsNoChangeForGitAnyMoreAndClosingReportsSuccess() async throws {
    let run = try DifftoolRun(
      committed: ["story.txt": "one\ntwo\nthree\n"], changed: ["story.txt": "one\n2\nthree\n"])
    try run.start()
    let comparison = try await run.nextComparison()
    let prompts = PromptRecorder()
    let controller = try await Self.window(for: comparison, of: run, prompts: prompts)
    #expect(!(try run.git(["diff", "--name-only"]).isEmpty))

    await Self.copyAllToTheWorkingCopy(in: controller)
    #expect(controller.window?.isDocumentEdited == true)
    #expect(Keys.of(.save, in: .diff) == Keys("s", .command))
    #expect(await controller.saveChangedFiles())

    #expect(try run.git(["diff", "--name-only"]).isEmpty)
    #expect(try run.text(of: "story.txt") == "one\ntwo\nthree\n")
    #expect(await controller.closeAskingFirst())
    let (status, output) = try await run.finish()
    #expect(status == 0, "\(output)")
    #expect(prompts.questions.isEmpty)
  }

  @Test func dontSaveReportsSuccessAndLeavesTheFileAndCancelKeepsTheWindow() async throws {
    let run = try DifftoolRun(
      committed: ["story.txt": "one\ntwo\nthree\n"], changed: ["story.txt": "one\n2\nthree\n"])
    try run.start()
    let prompts = PromptRecorder()
    let controller = try await Self.window(
      for: try await run.nextComparison(), of: run, prompts: prompts)
    await Self.copyAllToTheWorkingCopy(in: controller)

    #expect(!(await controller.closeAskingFirst()))
    #expect(controller.window?.isVisible == true)
    prompts.unsavedChangesChoice = .discard
    #expect(await controller.closeAskingFirst())

    let (status, output) = try await run.finish()
    #expect(status == 0, "\(output)")
    #expect(prompts.questions == Array(repeating: "save changes to story.txt", count: 2))
    #expect(try run.text(of: "story.txt") == "one\n2\nthree\n")
    #expect(try run.git(["diff", "--name-only"]) == "story.txt\n")
  }

  @Test func skippingTheRemainingFilesAsksSavesAndEndsTheRunWithFailure() async throws {
    let run = try DifftoolRun(
      committed: ["a.txt": "a\n", "b.txt": "b\n"], changed: ["a.txt": "A\n", "b.txt": "B\n"])
    try run.start()
    let prompts = PromptRecorder()
    prompts.unsavedChangesChoice = .save
    let controller = try await Self.window(
      for: try await run.nextComparison(), of: run, prompts: prompts)
    await Self.copyAllToTheWorkingCopy(in: controller)
    #expect(controller.canPerform(.skipRemainingFiles))

    #expect(await controller.skipRemainingFilesAskingFirst())

    // Git asks for no second file; a second comparison would wait until the time limit.
    let (status, output) = try await run.finish()
    #expect(status != 0, "\(output)")
    #expect(prompts.questions == ["save changes to a.txt"])
    #expect(try run.text(of: "a.txt") == "a\n")
    #expect(try run.text(of: "b.txt") == "B\n")
  }

  @Test func copiesOfGitAreNeverWritten() async throws {
    let run = try DifftoolRun(
      committed: ["story.txt": "one\ntwo\n"], changed: ["story.txt": "one\n2\n"])
    try run.git(["commit", "-q", "-am", "Second"])
    try run.start(["HEAD~1", "HEAD"])
    let comparison = try await run.nextComparison()
    let controller = try await Self.window(for: comparison, of: run, prompts: PromptRecorder())

    #expect(!controller.canPerform(.copyAllChangesToRight))
    #expect(!controller.canPerform(.copyAllChangesToLeft))
    controller.copyAllChangesToRight(nil)
    #expect(controller.copying == nil)
    #expect(!controller.canPerform(.save))
    controller.close()
    let (status, output) = try await run.finish()
    #expect(status == 0, "\(output)")
  }

  @Test func directoryDiffWritesTheFileOfTheWorkingTreeAndTheLinkStays() async throws {
    let run = try DifftoolRun(
      committed: ["src/story.txt": "one\ntwo\n", "same.txt": "same\n"],
      changed: ["src/story.txt": "one\n2\n"])
    try run.start(["--dir-diff"])
    let comparison = try await run.nextComparison()
    let link = comparison.right.appending(path: "src/story.txt")
    let destination = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
    let collection = FileCollection(
      comparing: FolderPair(left: comparison.left, right: comparison.right),
      linkFolder: run.folder.appending(path: "links"), workingTree: comparison.workingDirectory)
    collection.startComparing()
    await collection.waitUntilCompared()
    let prompts = PromptRecorder()
    let controller = try await Windows.controller(for: collection, prompts: prompts)
    let index = try #require(collection.files.firstIndex { $0.path == "src/story.txt" })
    controller.showFile(at: index)
    await controller.fileLoad?.value

    await Self.copyAllToTheWorkingCopy(in: controller)
    #expect(await controller.saveChangedFiles())

    #expect(try run.text(of: "src/story.txt") == "one\ntwo\n")
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == destination)
    #expect(try run.git(["diff", "--name-only"]).isEmpty)
    controller.close()
    await run.reply(0)
    let (status, output) = try await run.finish()
    #expect(status == 0, "\(output)")
    #expect(try run.text(of: "src/story.txt") == "one\ntwo\n")
  }
}
