import Foundation
import Testing

@testable import SeamergeUI

/// The two folders of `git difftool --dir-diff`, paired by path.
struct FolderComparisonTests {
  @Test func onlyChangedNewAndDeletedFilesAreShown() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "FolderComparison-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer {
      do {
        try FileManager.default.removeItem(at: folder)
      } catch {
        Issue.record(error, "The folders could not be removed")
      }
    }
    let write = { (path: String, text: String) throws in
      let url = folder.appending(path: path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(text.utf8).write(to: url)
    }
    try write("left/same.txt", "same\n")
    try write("right/same.txt", "same\n")
    try write("left/sub/changed.txt", "old\n")
    try write("left/deleted.txt", "gone\n")
    try write("right/added.txt", "new\n")
    try write("repository/sub/changed.txt", "new\n")
    let right = folder.appending(path: "right/sub", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: right.appending(path: "changed.txt"),
      withDestinationURL: folder.appending(path: "repository/sub/changed.txt"))

    let files = await FolderComparison.files(
      left: folder.appending(path: "left"), right: folder.appending(path: "right"),
      workingTree: folder.appending(path: "repository"), linkFolder: folder.appending(path: "links")
    )

    #expect(files.map(\.path) == ["added.txt", "deleted.txt", "sub/changed.txt"])
    #expect(files.map(\.change) == [.added, .deleted, .modified])
    let changed = try #require(files.last)
    #expect(changed.difftool.rightRole == .workingCopy)
    #expect(changed.new.url.path.hasSuffix("repository/sub/changed.txt"))
  }

  /// A link that is a file of the repository is compared by its target and never followed, a
  /// hanging one too; only a link into the working tree is the working copy.
  @Test func linksAreComparedByTheirTargetsUnlessTheyLeadIntoTheWorkingTree() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "FolderComparison-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer {
      do {
        try FileManager.default.removeItem(at: folder)
      } catch {
        Issue.record(error, "The folders could not be removed")
      }
    }
    for name in ["left", "right", "repository"] {
      try FileManager.default.createDirectory(
        at: folder.appending(path: name), withIntermediateDirectories: true)
    }
    let link = { (path: String, target: String) throws in
      try FileManager.default.createSymbolicLink(
        atPath: folder.appending(path: path).path, withDestinationPath: target)
    }
    try link("left/hosts", "/etc/hosts")
    try link("right/hosts", "/etc/services")
    try link("left/same", "/etc/hosts")
    try link("right/same", "/etc/hosts")
    try link("left/gone", "missing-before")
    try link("right/gone", "missing-after")
    try link("repository/own", "../elsewhere")
    try link("right/own", folder.appending(path: "repository/own").path)

    let files = await FolderComparison.files(
      left: folder.appending(path: "left"), right: folder.appending(path: "right"),
      workingTree: folder.appending(path: "repository"), linkFolder: folder.appending(path: "links")
    )

    #expect(files.map(\.path) == ["gone", "hosts", "own"])
    let text = { (url: URL) throws -> String in
      url.path == "/dev/null" ? "" : try String(contentsOf: url, encoding: .utf8)
    }
    let texts = try files.map { [try text($0.old.url), try text($0.new.url)] }
    #expect(
      texts == [
        ["missing-before", "missing-after"], ["/etc/hosts", "/etc/services"], ["", "../elsewhere"],
      ])
    #expect(files.allSatisfy { $0.difftool.rightRole == .after })
  }
}
