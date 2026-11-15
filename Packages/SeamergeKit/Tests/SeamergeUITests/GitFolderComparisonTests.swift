import Foundation
import Testing

@testable import SeamergeUI

/// The two folders of `git difftool --dir-diff`, compared like any two folders: a link of Git to
/// a file of the working tree stands for that file, the working copy, and the sides are named as
/// Git names them.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct GitFolderComparisonTests {
  @Test func linkOfGitToAFileOfTheWorkingTreeIsTheWorkingCopy() async throws {
    let folders = try SampleFolders(left: "left", right: "right")
    let tree = try Self.directoryDiff(in: folders)

    let collection = await Self.compared(folders, workingTree: tree)

    #expect(collection.files.map(\.path) == ["added.txt", "deleted.txt", "same.txt", "sub/a.txt"])
    #expect(collection.files.map(\.change) == [.added, .deleted, .identical, .modified])
    let changed = try #require(collection.files.last)
    #expect(changed.difftool.leftRole == .before)
    #expect(changed.difftool.rightRole == .workingCopy)
    #expect(
      changed.new.url.resolvingSymlinksInPath()
        == tree.appending(path: "sub/a.txt")
        .resolvingSymlinksInPath())
    #expect(collection.folders == folders.pair)
    #expect(collection.namingFolders == nil)
  }

  @Test func withoutAWorkingTreeTheLinkIsComparedByItsTargetAndTheFoldersNameTheSides()
    async throws
  {
    let folders = try SampleFolders(left: "left", right: "right")
    let tree = try Self.directoryDiff(in: folders)

    let collection = await FileCollection.compared(folders)

    let changed = try #require(collection.files.first { $0.path == "sub/a.txt" })
    #expect(changed.change == .modified)
    #expect(changed.difftool.rightRole == .after)
    #expect(
      try String(contentsOf: changed.new.url, encoding: .utf8)
        == tree.appending(path: "sub/a.txt").path)
    #expect(collection.namingFolders == folders.pair)
  }

  /// A link that is a file of the repository is compared by its target and never followed, a
  /// hanging one too; a link of Git to a file of the working tree that is a link itself is
  /// compared by that file's target.
  @Test func otherLinksAreComparedByTheirTargets() async throws {
    let folders = try SampleFolders(left: "left", right: "right")
    let tree = folders.folder.appending(path: "repository", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
    let link = { (url: URL, target: String) throws in
      try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: target)
    }
    try link(folders.left.appending(path: "hosts"), "/etc/hosts")
    try link(folders.right.appending(path: "hosts"), "/etc/services")
    try link(folders.left.appending(path: "same"), "/etc/hosts")
    try link(folders.right.appending(path: "same"), "/etc/hosts")
    try link(folders.left.appending(path: "gone"), "missing-before")
    try link(folders.right.appending(path: "gone"), "missing-after")
    try link(tree.appending(path: "own"), "../elsewhere")
    try link(folders.right.appending(path: "own"), tree.appending(path: "own").path)

    let collection = await Self.compared(folders, workingTree: tree)

    let text = { (url: URL) throws -> String in
      url.path == "/dev/null" ? "" : try String(contentsOf: url, encoding: .utf8)
    }
    let files = collection.files.filter { $0.change != .identical }
    #expect(files.map(\.path) == ["gone", "hosts", "own"])
    #expect(
      try files.map { [try text($0.old.url), try text($0.new.url)] } == [
        ["missing-before", "missing-after"], ["/etc/hosts", "/etc/services"], ["", "../elsewhere"],
      ])
    #expect(files.allSatisfy { $0.difftool.rightRole == .after })
    #expect(collection.files.first { $0.path == "same" }?.change == .identical)
  }

  @Test func windowOfADirectoryDiffNamesTheSidesAsGitDoes() async throws {
    let folders = try SampleFolders(left: "left", right: "right")
    let tree = try Self.directoryDiff(in: folders)
    let collection = FileCollection(
      comparer: FolderComparer(
        folders: folders.pair, linkFolder: folders.folder.appending(path: "links"),
        workingTree: tree))
    let controller = try await Windows.controller(for: collection)

    collection.startComparing()
    await collection.waitUntilCompared()
    await controller.fileLoad?.value
    controller.showFile(at: try #require(collection.files.firstIndex { $0.path == "sub/a.txt" }))
    await controller.fileLoad?.value

    #expect(controller.window?.title == "sub/a.txt")
    #expect(controller.window?.subtitle.contains("left ↔ right") == false)
    #expect(
      controller.layout.sourcePanes.map { $0.pane.accessibilityLabel() } == [
        "A, sub/a.txt, Earlier Version", "B, sub/a.txt, Working Copy",
      ])
    #expect(controller.canPerform(.toggleIdenticalFiles))
    #expect(controller.canPerform(.filterFiles))
  }

  /// A collection that compares `folders` of a directory diff in `workingTree`, compared once.
  private static func compared(
    _ folders: borrowing SampleFolders, workingTree: URL
  ) async -> FileCollection {
    let collection = FileCollection(
      comparer: FolderComparer(
        folders: folders.pair, linkFolder: folders.folder.appending(path: "links"),
        workingTree: workingTree),
      latency: .milliseconds(50))
    collection.startComparing()
    await collection.waitUntilCompared()
    return collection
  }

  /// Fills `folders` as `git difftool --dir-diff` does for a working tree beside them, and
  /// returns the working tree: a file changed in the working tree, linked; a file the same in
  /// both, linked; a deleted file; and a file that is new in a commit, copied.
  private static func directoryDiff(in folders: borrowing SampleFolders) throws -> URL {
    let tree = folders.folder.appending(path: "repository", directoryHint: .isDirectory)
    try folders.write("old\n", to: folders.left.appending(path: "sub/a.txt"))
    try folders.write("new\n", to: tree.appending(path: "sub/a.txt"))
    try folders.write("same\n", to: folders.left.appending(path: "same.txt"))
    try folders.write("same\n", to: tree.appending(path: "same.txt"))
    try folders.write("gone\n", to: folders.left.appending(path: "deleted.txt"))
    try folders.write("new\n", to: folders.right.appending(path: "added.txt"))
    try FileManager.default.createDirectory(
      at: folders.right.appending(path: "sub"), withIntermediateDirectories: true)
    for path in ["sub/a.txt", "same.txt"] {
      try FileManager.default.createSymbolicLink(
        at: folders.right.appending(path: path), withDestinationURL: tree.appending(path: path))
    }
    return tree
  }
}
