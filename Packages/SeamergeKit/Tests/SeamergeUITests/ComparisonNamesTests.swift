import AppKit
import GitSupport
import MergeModel
import Testing

@testable import SeamergeUI

/// How the window names the sides of a comparison that Git or Tower hands over as copies: the
/// path in the repository as title, a role only where the names are the same, and a missing side
/// as the new or the deleted file.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct ComparisonNamesTests {
  private static let temporary = URL(
    filePath: "/private/var/folders/xy/T/", directoryHint: .isDirectory)

  @Test func missingEarlierSideIsTheNewFileAndEmpty() async throws {
    let session = try await Session.diff(
      old: SourceFile(bytes: Data(), label: "added.txt", url: URL(filePath: "/dev/null")),
      new: SourceFile(bytes: Data("one\ntwo\n".utf8), label: "added.txt"), mode: .windowDefault)
    let context = SessionContext(
      difftool: DifftoolContext(path: "added.txt", leftRole: .before, rightRole: .workingCopy))

    let controller = try Windows.controller(for: session, context: context)

    #expect(try #require(controller.window).title == "added.txt")
    #expect(labels(of: controller) == ["A, New File", "B, added.txt"])
    #expect(session.inputs.a.text == "")
  }

  /// Git, also the Git inside Tower, passes `/dev/null` for the missing side of a new file.
  @Test func newFileFromGitShowsAsAddedNextToAnEmptySide() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "ComparisonNames-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    let added = folder.appending(path: "tsconfig.storybook.json")
    try Data("{\n  \"extends\": \"./tsconfig.json\"\n}\n".utf8).write(to: added)

    let session = try await Session.loadDiff(
      old: SessionFile(url: URL(filePath: "/dev/null"), label: "null"),
      new: SessionFile(url: added, label: "tsconfig.storybook.json"), mode: .windowDefault)
    let controller = try Windows.controller(for: session)

    #expect(session.inputs.a.text == "")
    #expect(session.inputs.b.text?.hasPrefix("{") == true)
    #expect(try #require(controller.window).title == "tsconfig.storybook.json")
    #expect(labels(of: controller) == ["A, New File", "B, tsconfig.storybook.json"])
  }

  @Test func missingLaterSideIsTheDeletedFile() async throws {
    let session = try await Session.diff(
      old: SourceFile(
        bytes: Data("gone\n".utf8), label: "removed.txt",
        url: Self.temporary.appending(path: "git-blob-taXZ1B/removed.txt")),
      new: SourceFile(bytes: Data(), label: "removed.txt", url: URL(filePath: "/dev/null")),
      mode: .windowDefault)

    let controller = try Windows.controller(for: session)

    #expect(try #require(controller.window).title == "removed.txt")
    #expect(labels(of: controller) == ["A, removed.txt", "B, Deleted File"])
  }

  @Test func copiesOfTheSameNameAreTheEarlierAndTheLaterVersion() async throws {
    let session = try await Session.diff(
      old: SourceFile(
        bytes: Data("a\n".utf8), label: "notes.txt",
        url: Self.temporary.appending(path: "git-blob-QQ1247/notes.txt")),
      new: SourceFile(
        bytes: Data("b\n".utf8), label: "notes.txt",
        url: Self.temporary.appending(path: "git-blob-sxPPvm/notes.txt")),
      mode: .windowDefault)

    let controller = try Windows.controller(for: session)

    #expect(
      labels(of: controller) == [
        "A, notes.txt, Earlier Version", "B, notes.txt, Later Version",
      ])
    let header = try #require(SideHeader.headers(of: session, context: SessionContext())[.a])
    #expect(header.details.location == "/private/var/folders/xy/T/git-blob-QQ1247/notes.txt")
  }

  @Test func filesOfDifferentNamesNeedNoRole() async throws {
    let session = try await Session.diff(
      old: SourceFile(bytes: Data("a\n".utf8), label: "old.txt"),
      new: SourceFile(bytes: Data("b\n".utf8), label: "new.txt"), mode: .windowDefault)

    let controller = try Windows.controller(for: session)

    #expect(labels(of: controller) == ["A, old.txt", "B, new.txt"])
  }

  /// A change in the working tree as Fork hands it over: the copy of the index from its
  /// temporary folder and the working copy, named by the path the command line found in the
  /// working tree, as the app names both sides with it.
  @Test func changeInTheWorkingTreeFromForkIsNamedByItsPathInTheRepository() async throws {
    let path = "sub dir/changed file.txt"
    let session = try await Session.diff(
      old: SourceFile(
        bytes: Data("alpha\nbeta\n".utf8), label: path,
        url: Self.temporary.appending(path: "fork/staged/sub dir/changed file.txt")),
      new: SourceFile(
        bytes: Data("alpha\nBETA changed\n".utf8), label: path,
        url: URL(filePath: "/Users/ada/git tests/diff/sub dir/changed file.txt")),
      mode: .windowDefault)
    let context = SessionContext(
      difftool: DifftoolContext(path: path, leftRole: .before, rightRole: .workingCopy))

    let controller = try Windows.controller(for: session, context: context)

    let window = try #require(controller.window)
    #expect(window.title == path)
    #expect(window.accessibilityTitle() == "\(path), 1 change")
    #expect(
      labels(of: controller) == [
        "A, \(path), Earlier Version", "B, \(path), Working Copy",
      ])
  }

  @Test(arguments: [Look.light, .dark])
  func newFileIsPictured(look: Look) async throws {
    let session = try await Session.diff(
      old: SourceFile(
        bytes: Data(), label: "Sources/Farewell.swift", url: URL(filePath: "/dev/null")),
      new: SourceFile(
        bytes: Data(SampleDiffs.greetingNew.utf8), label: "Sources/Farewell.swift"),
      mode: .windowDefault)
    let context = SessionContext(
      difftool: DifftoolContext(
        path: "Sources/Farewell.swift", leftRole: .before, rightRole: .workingCopy))
    try Windows.picture(session, context: context, look: look, named: "diff-new-file-\(look.name)")
  }

  private func labels(of controller: SessionWindowController) -> [String] {
    controller.layout.sourcePanes.map { $0.pane.accessibilityLabel() ?? "" }
  }
}
