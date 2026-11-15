import Foundation
import Testing

@testable import SeamergeUI

/// Two folders compared entry by entry: how paths pair, what counts as changed, what is left out
/// or cannot be read, and links, which are never followed.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct FolderComparerTests {
  @Test func decomposedAndComposedUmlautsPairAsOneFile() async throws {
    let folders = try SampleFolders()
    let decomposed = "Gru\u{0308}sse/A\u{0308}nderung.txt"
    let composed = "Gr\u{00FC}sse/\u{00C4}nderung.txt"
    try folders.write("same\n", to: folders.left.appending(path: decomposed))
    try folders.write("same\n", to: folders.right.appending(path: composed))

    let collection = await FileCollection.compared(folders)

    #expect(collection.files.count == 1)
    #expect(collection.files.first?.change == .identical)
    #expect(collection.pairedCount == 1)
  }

  @Test func sameSizeWithOtherBytesIsModifiedAndEqualBytesAreIdentical() async throws {
    let folders = try SampleFolders()
    try folders.write("same-size.txt", left: "abc\n", right: "abd\n")
    try folders.write("equal.txt", left: "abc\n", right: "abc\n")
    try folders.write("longer.txt", left: "abc\n", right: "abcd\n")
    let large = String(repeating: "x", count: 200_000)
    try folders.write("large.txt", left: large + "a", right: large + "b")

    let collection = await FileCollection.compared(folders)

    let changes = Dictionary(uniqueKeysWithValues: collection.files.map { ($0.path, $0.change) })
    #expect(
      changes == [
        "equal.txt": .identical, "large.txt": .modified, "longer.txt": .modified,
        "same-size.txt": .modified,
      ])
  }

  @Test func newDeletedAndSkippedEntries() async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    try folders.write("Sources/.git", left: "gitdir: elsewhere\n", right: nil)

    let collection = await FileCollection.compared(folders)

    let paths = collection.files.map(\.path)
    #expect(!paths.contains { $0.hasPrefix(".git") || $0.contains("/.git") })
    #expect(!paths.contains { $0.hasSuffix(".DS_Store") })
    let change = { (path: String) in collection.files.first { $0.path == path }?.change }
    #expect(change("Sources/Orders/Discount.swift") == .added)
    #expect(change("prices.txt") == .deleted)
    #expect(change("LICENSE") == .identical)
    #expect(change("VERSION") == .modified)
    #expect(paths == paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
  }

  @Test func unreadableFoldersAndFilesStandWithTheirReason() async throws {
    let folders = try SampleFolders()
    try folders.write("Logs/today.txt", left: "left\n", right: "right\n")
    try folders.write("secret.txt", left: "abc\n", right: "abd\n")
    try FileManager.default.setAttributes(
      [.posixPermissions: 0], ofItemAtPath: folders.left.appending(path: "Logs").path)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0], ofItemAtPath: folders.right.appending(path: "secret.txt").path)

    let collection = await FileCollection.compared(folders)

    let reason = "You don’t have permission to read it."
    let changes = Dictionary(uniqueKeysWithValues: collection.files.map { ($0.path, $0.change) })
    #expect(changes["Logs"] == .unreadable(reason: reason))
    #expect(changes["Logs/today.txt"] == nil, "The files below a folder that cannot be read")
    #expect(changes["secret.txt"] == .unreadable(reason: reason))
    let presentation = try #require(changes["Logs"]).presentation
    #expect(presentation.word == "Can’t Read")
    #expect(presentation.toolTip(for: "Logs") == "Logs (Can’t Read: \(reason))")
  }

  /// A link to the folder above it would make a loop if it were followed; it is compared by its
  /// target instead, and shown as the text of that target.
  @Test func linksAreComparedByTheirTargetsAndNeverFollowed() async throws {
    let folders = try SampleFolders()
    for root in [folders.left, folders.right] {
      try FileManager.default.createDirectory(
        at: root.appending(path: "nested"), withIntermediateDirectories: true)
      try FileManager.default.createSymbolicLink(
        atPath: root.appending(path: "nested/loop").path, withDestinationPath: "..")
    }
    try FileManager.default.createSymbolicLink(
      atPath: folders.left.appending(path: "current").path, withDestinationPath: "v1")
    try FileManager.default.createSymbolicLink(
      atPath: folders.right.appending(path: "current").path, withDestinationPath: "v2")

    let collection = await FileCollection.compared(folders)

    let changes = Dictionary(uniqueKeysWithValues: collection.files.map { ($0.path, $0.change) })
    #expect(changes == ["current": .modified, "nested/loop": .identical])
    let current = try #require(collection.files.first { $0.path == "current" })
    #expect(try String(contentsOf: current.old.url, encoding: .utf8) == "v1")
    #expect(try String(contentsOf: current.new.url, encoding: .utf8) == "v2")
  }

  @Test func pathsDifferingOnlyInCasePairAsTheLeftFileSystemSays() async throws {
    let folders = try SampleFolders()
    try folders.write("readme.md", left: "same\n", right: nil)
    try folders.write("README.md", left: nil, right: "same\n")
    let comparer = FolderComparer(
      folders: folders.pair, linkFolder: folders.folder.appending(path: "links"))

    let pairs = comparer.pairs(at: "")

    #expect(pairs.count == (comparer.isCaseSensitive ? 2 : 1))
  }
}

/// The names that tell two folders apart in the headers and the subtitle.
struct FolderPairTests {
  @Test func foldersOfTheSameNameAreToldApartByTheShortestEndsOfTheirPaths() {
    let pair = FolderPair(
      left: URL(filePath: "/Users/me/app/src", directoryHint: .isDirectory),
      right: URL(filePath: "/Users/me/lib/src", directoryHint: .isDirectory))

    #expect(pair.distinctNames == ("app/src", "lib/src"))
    #expect(pair.title == "app/src ↔ lib/src")
  }

  @Test func foldersOfOtherNamesKeepTheirNames() {
    let pair = FolderPair(
      left: URL(filePath: "/a/Seamerge 0.2"), right: URL(filePath: "/b/c/Seamerge 0.3"))

    #expect(pair.distinctNames == ("Seamerge 0.2", "Seamerge 0.3"))
  }
}
