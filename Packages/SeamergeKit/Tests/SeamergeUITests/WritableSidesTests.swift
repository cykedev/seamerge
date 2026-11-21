import FolderCompareTestSupport
import Foundation
import GitSupport
import MergeModel
import Testing

@testable import FolderCompare
@testable import SeamergeUI

/// Which files of a comparison copying a change may write to: from Git or Tower only the working
/// copy, else every file the user chose, and in either case only an ordinary file that can be
/// written.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct WritableSidesTests {
  /// The file at `url`, labelled with its name.
  private static func file(_ url: URL) -> SessionFile {
    SessionFile(url: url, label: url.lastPathComponent)
  }

  /// The roles of the files that `writable` lets copying write to.
  private static func roles(_ writable: WritableSides) -> [Role] {
    [Role.a, .b].filter { writable.contains($0) }
  }

  /// A file in the working tree, `tree/main.swift`, and a copy of an earlier version beside it,
  /// as Git writes one into its temporary folder.
  private static func gitFiles(in folders: borrowing SampleFolders) throws -> (
    copy: URL, workingCopy: URL
  ) {
    let copy = folders.left.appending(path: "main_BASE.swift")
    let workingCopy = folders.right.appending(path: "main.swift")
    try folders.write("let a = 1\n", to: copy)
    try folders.write("let a = 2\n", to: workingCopy)
    return (copy, workingCopy)
  }

  @Test func gitWithTheWorkingCopyOnTheRightWritesOnlyTheRight() throws {
    let folders = try SampleFolders()
    let files = try Self.gitFiles(in: folders)
    let context = SessionContext(
      difftool: DifftoolContext(path: "main.swift", leftRole: .before, rightRole: .workingCopy))

    let writable = WritableSides(
      old: Self.file(files.copy), new: Self.file(files.workingCopy), context: context)

    #expect(Self.roles(writable) == [.b])
  }

  @Test func gitWithTheWorkingCopyOnTheLeftWritesOnlyTheLeft() throws {
    let folders = try SampleFolders()
    let files = try Self.gitFiles(in: folders)
    let context = SessionContext(
      difftool: DifftoolContext(path: "main.swift", leftRole: .workingCopy, rightRole: .after))

    let writable = WritableSides(
      old: Self.file(files.workingCopy), new: Self.file(files.copy), context: context)

    #expect(Self.roles(writable) == [.a])
  }

  @Test func gitBetweenTwoCommitsWritesNeither() throws {
    let folders = try SampleFolders()
    let files = try Self.gitFiles(in: folders)
    let context = SessionContext(
      difftool: DifftoolContext(path: "main.swift", leftRole: .before, rightRole: .after))

    let writable = WritableSides(
      old: Self.file(files.copy), new: Self.file(files.workingCopy), context: context)

    #expect(writable.isEmpty)
  }

  @Test func copyOfGitIsNotWrittenThoughTheDiskWouldAllowIt() throws {
    let folders = try SampleFolders()
    let files = try Self.gitFiles(in: folders)
    try #require(FileManager.default.isWritableFile(atPath: files.copy.path))
    let context = SessionContext(
      difftool: DifftoolContext(path: "main.swift", leftRole: .before, rightRole: .workingCopy))

    let writable = WritableSides(
      old: Self.file(files.copy), new: Self.file(files.workingCopy), context: context)

    #expect(!writable.contains(.a))
  }

  @Test func directoryDiffWritesTheWorkingCopyThatALinkOfGitLeadsTo() async throws {
    let folders = try SampleFolders(left: "left", right: "right")
    let tree = folders.folder.appending(path: "repository", directoryHint: .isDirectory)
    try folders.write("old\n", to: folders.left.appending(path: "a.txt"))
    try folders.write("new\n", to: tree.appending(path: "a.txt"))
    try FileManager.default.createSymbolicLink(
      at: folders.right.appending(path: "a.txt"), withDestinationURL: tree.appending(path: "a.txt"))
    try folders.write("added in a commit\n", to: folders.right.appending(path: "b.txt"))
    let collection = FileCollection(
      comparer: FolderComparer(
        folders: folders.pair, linkFolder: folders.folder.appending(path: "links"),
        workingTree: tree),
      latency: .milliseconds(50))
    collection.startComparing()
    await collection.waitUntilCompared()
    try #require(collection.files.map(\.path) == ["a.txt", "b.txt"])

    let writable = collection.files.map { file in
      Self.roles(
        WritableSides(
          old: file.old, new: file.new,
          context: SessionContext(difftool: file.difftool, folders: collection.namingFolders)))
    }

    #expect(writable == [[.b], []])
  }

  @Test func linkToTheWorkingCopyCountsAsTheFileItLeadsTo() throws {
    let folders = try SampleFolders()
    let files = try Self.gitFiles(in: folders)
    let link = folders.folder.appending(path: "main.swift")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: files.workingCopy)
    let context = SessionContext(
      difftool: DifftoolContext(path: "main.swift", leftRole: .before, rightRole: .workingCopy))

    let writable = WritableSides(
      old: Self.file(files.copy), new: Self.file(link), context: context)

    #expect(Self.roles(writable) == [.b])
  }

  @Test func directoryDiffWithCopiesInsteadOfLinksWritesNothing() async throws {
    let folders = try SampleFolders(left: "left", right: "right")
    let tree = folders.folder.appending(path: "repository", directoryHint: .isDirectory)
    try folders.write("new\n", to: tree.appending(path: "a.txt"))
    try folders.write("a.txt", left: "old\n", right: "new\n")
    let collection = FileCollection(
      comparer: FolderComparer(
        folders: folders.pair, linkFolder: folders.folder.appending(path: "links"),
        workingTree: tree),
      latency: .milliseconds(50))
    collection.startComparing()
    await collection.waitUntilCompared()
    let file = try #require(collection.files.first)

    let writable = WritableSides(
      old: file.old, new: file.new,
      context: SessionContext(difftool: file.difftool, folders: collection.namingFolders))

    #expect(writable.isEmpty)
  }

  @Test func towerWritesTheSideThatLiesInTheWorkingTree() throws {
    let folders = try SampleFolders(left: "T", right: "repository")
    let files = try Self.gitFiles(in: folders)
    let path = try #require(
      DifftoolContext.inferredPath(
        leftFile: files.copy, rightFile: files.workingCopy, workingDirectory: folders.right,
        temporaryDirectory: folders.left))
    let difftool = DifftoolContext.detect(
      path: path, leftFile: files.copy, rightFile: files.workingCopy,
      workingDirectory: folders.right, environment: [:])

    let writable = WritableSides(
      old: Self.file(files.copy), new: Self.file(files.workingCopy),
      context: SessionContext(difftool: difftool))

    #expect(Self.roles(writable) == [.b])
  }

  @Test func compareFilesWritesBothFiles() throws {
    let folders = try SampleFolders()
    try folders.write("notes.txt", left: "one\n", right: "two\n")

    let writable = WritableSides(
      old: Self.file(folders.left.appending(path: "notes.txt")),
      new: Self.file(folders.right.appending(path: "notes.txt")), context: SessionContext())

    #expect(Self.roles(writable) == [.a, .b])
  }

  @Test func compareFilesLeavesAReadOnlyFileAlone() throws {
    let folders = try SampleFolders()
    try folders.write("notes.txt", left: "one\n", right: "two\n")
    let readOnly = folders.right.appending(path: "notes.txt")
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: readOnly.path)

    let writable = WritableSides(
      old: Self.file(folders.left.appending(path: "notes.txt")), new: Self.file(readOnly),
      context: SessionContext())

    #expect(Self.roles(writable) == [.a])
  }

  @Test func compareFilesNeverWritesTheMissingSideOfANewFile() throws {
    let folders = try SampleFolders()
    try folders.write("one\n", to: folders.right.appending(path: "notes.txt"))

    let writable = WritableSides(
      old: Self.file(URL(filePath: "/dev/null")),
      new: Self.file(folders.right.appending(path: "notes.txt")), context: SessionContext())

    #expect(Self.roles(writable) == [.b])
  }

  @Test func compareFilesWritesAFileInTheTemporaryFolder() throws {
    let folders = try SampleFolders()
    try folders.write("notes.txt", left: "one\n", right: "two\n")
    let temporary = folders.right.appending(path: "notes.txt")
    try #require(
      temporary.resolvingSymlinksInPath().path.hasPrefix(
        FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path))

    let writable = WritableSides(
      old: Self.file(folders.left.appending(path: "notes.txt")), new: Self.file(temporary),
      context: SessionContext())

    #expect(writable.contains(.b))
  }

  /// `seamerge a b` in a terminal outside Git: the command infers no path for two ordinary files,
  /// so the request carries no roles and the window no context of Git.
  @Test func commandLineOutsideGitWritesBothFiles() throws {
    let folders = try SampleFolders()
    try folders.write("notes.txt", left: "one\n", right: "two\n")
    let old = folders.left.appending(path: "notes.txt")
    let new = folders.right.appending(path: "notes.txt")
    let path = DifftoolContext.inferredPath(
      leftFile: old, rightFile: new, workingDirectory: folders.folder,
      temporaryDirectory: URL(filePath: "/private/var/folders/xy/T/", directoryHint: .isDirectory))
    try #require(path == nil)

    let writable = WritableSides(
      old: Self.file(old), new: Self.file(new), context: SessionContext(difftool: nil))

    #expect(Self.roles(writable) == [.a, .b])
  }

  @Test func foldersTheUserChoseWriteBothFilesOfAPair() async throws {
    let folders = try SampleFolders()
    try folders.write("notes.txt", left: "one\n", right: "two\n")
    let collection = await FileCollection.compared(folders)
    let file = try #require(collection.files.first)
    try #require(collection.namingFolders != nil)

    let writable = WritableSides(
      old: file.old, new: file.new,
      context: SessionContext(difftool: file.difftool, folders: collection.namingFolders))

    #expect(Self.roles(writable) == [.a, .b])
  }

  @Test func swappingTheSidesOfTheWindowTakesTheWritableFileAlong() async throws {
    let folders = try SampleFolders()
    let files = try Self.gitFiles(in: folders)
    let context = SessionContext(
      difftool: DifftoolContext(path: "main.swift", leftRole: .before, rightRole: .workingCopy))
    let session = try await Session.diff(
      old: SourceFile(contentsOf: files.copy, label: "main.swift"),
      new: SourceFile(contentsOf: files.workingCopy, label: "main.swift"))
    let controller = try Windows.controller(for: session, context: context)
    let writable = WritableSides(
      old: Self.file(files.copy), new: Self.file(files.workingCopy), context: context)
    #expect(writable.allowsCopyToRight(in: controller.presentation.arrangement))
    #expect(!writable.allowsCopyToLeft(in: controller.presentation.arrangement))

    controller.swapSides(nil)

    let arrangement = controller.presentation.arrangement
    #expect(session.inputs[arrangement.leadingRole]?.url == files.workingCopy)
    #expect(writable.allowsCopyToLeft(in: arrangement))
    #expect(!writable.allowsCopyToRight(in: arrangement))
  }
}
