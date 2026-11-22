import Foundation
import GitSupport
import MergeModel
import Testing

@testable import FolderCompare
@testable import SeamergeUI

/// Which file of a collection the window shows: the files its list shows, the next and the
/// previous file, the file in view after the files changed, and the place kept in each file.
@MainActor
struct CollectionNavigatorTests {
  /// A file at `path` whose sides are named after `folder`, without reading them.
  private static func file(
    _ path: String, change: CollectedFile.Change = .modified, folder: String = "new"
  ) -> CollectedFile {
    CollectedFile(
      old: SessionFile(url: URL(filePath: "/tmp/old/\(path)"), label: path),
      new: SessionFile(url: URL(filePath: "/tmp/\(folder)/\(path)"), label: path),
      difftool: DifftoolContext(path: path), change: change)
  }

  /// A file at `path`, number `number` in a run of Git of four files.
  private static func numbered(_ path: String, _ number: Int) -> CollectedFile {
    var file = file(path)
    file.difftool = DifftoolContext(
      path: path, filePosition: FilePosition(number: number, count: 4))
    return file
  }

  /// Four files of a commit in the order of Git.
  private static let commit = [
    numbered("Sources/Orders/OrderService.swift", 1), numbered("README.md", 2),
    numbered("Sources/Orders/Discount.swift", 3), numbered("Tests/OrderTests.swift", 4),
  ]

  private static let files = [
    file("a.txt"), file("b.txt", change: .identical), file("c.txt"), file("d.txt"),
  ]

  private func navigator(
    showing index: Int, showsIdenticalFiles: Bool = false
  ) -> CollectionNavigator {
    let navigator = CollectionNavigator(
      collection: FileCollection(files: Self.files), showsIdenticalFiles: showsIdenticalFiles)
    navigator.listFiles()
    _ = navigator.go(toFileAt: index)
    return navigator
  }

  @Test func listLeavesOutIdenticalFilesUntilAskedForThem() {
    #expect(navigator(showing: 0).listedFiles.map(\.path) == ["a.txt", "c.txt", "d.txt"])
    #expect(
      navigator(showing: 0, showsIdenticalFiles: true).listedFiles.map(\.path)
        == ["a.txt", "b.txt", "c.txt", "d.txt"])
  }

  @Test func nextAndPreviousFileOfAFileTheListLeavesOutAreTheListedOnesBesideIt() {
    let navigator = navigator(showing: 1)

    #expect(navigator.shownRow == nil)
    #expect(navigator.filePosition == nil)
    #expect(navigator.neighborIndex(forward: true) == 2)
    #expect(navigator.neighborIndex(forward: false) == 0)
  }

  @Test func positionCountsTheFilesTheFilterLetsThrough() {
    let navigator = navigator(showing: 2)
    #expect(navigator.filePosition == FilePosition(number: 2, count: 4))

    navigator.changeFilter { $0.text = "d" }
    #expect(navigator.listedFiles.map(\.path) == ["d.txt"])
    #expect(navigator.filePosition == nil)
    #expect(navigator.neighborIndex(forward: true) == 3)
  }

  @Test func fileInViewThatWentGivesWayToTheNextFileListed() {
    let navigator = navigator(showing: 2)

    navigator.collection.take(.replaced([Self.files[0], Self.files[1], Self.files[3]]))
    guard case .went(let next) = navigator.followShownFile() else {
      Issue.record("The file in view went")
      return
    }
    navigator.listFiles()

    #expect(navigator.shownFile == nil)
    #expect(navigator.neighborIndex(forward: true) == nil)
    #expect(navigator.listedIndex(from: next) == 2)
  }

  @Test func fileInViewWithOtherSidesIsReadAnewAndOneWithAnotherChangeOnlyIsNot() {
    let navigator = navigator(showing: 2)
    let moved = Self.file("c.txt", folder: "moved")
    let identical = Self.file("c.txt", change: .identical)

    navigator.collection.take(.replaced([Self.files[0], identical, Self.files[3]]))
    #expect(navigator.followShownFile() == .stays)
    #expect(navigator.shownFile == identical)
    #expect(navigator.fileIndex == 1)

    navigator.collection.take(.replaced([Self.files[0], moved, Self.files[3]]))
    #expect(navigator.followShownFile() == .readsAnew(moved))
  }

  @Test func listGroupsTheFilesOfGitByFolderAndNextFileAndPositionFollowIt() {
    let navigator = CollectionNavigator(
      collection: FileCollection(files: Self.commit), showsIdenticalFiles: false)
    navigator.listFiles()

    #expect(
      navigator.listedFiles.map(\.path) == [
        "README.md", "Sources/Orders/OrderService.swift", "Sources/Orders/Discount.swift",
        "Tests/OrderTests.swift",
      ])
    #expect(navigator.listedGroups.groups.map(\.folder) == ["", "Sources/Orders", "Tests"])
    _ = navigator.go(toFileAt: 1)
    #expect(navigator.neighborIndex(forward: false) == nil)
    #expect(navigator.neighborIndex(forward: true) == 0)
    _ = navigator.go(toFileAt: 2)
    #expect(navigator.neighborIndex(forward: false) == 0)
    #expect(navigator.neighborIndex(forward: true) == 3)
    #expect(navigator.filePosition == FilePosition(number: 3, count: 4))
  }

  @Test func filterMatchesTheFolderForAllItsFilesAndTheNameForOneAndDropsEmptyFolders() {
    let navigator = CollectionNavigator(
      collection: FileCollection(files: Self.commit), showsIdenticalFiles: false)
    navigator.listFiles()

    navigator.changeFilter { $0.text = "orders" }
    #expect(
      navigator.listedFiles.map(\.path) == [
        "Sources/Orders/OrderService.swift", "Sources/Orders/Discount.swift",
      ])
    #expect(navigator.listedGroups.groups.map(\.folder) == ["Sources/Orders"])

    navigator.changeFilter { $0.text = "discount" }
    #expect(navigator.listedFiles.map(\.path) == ["Sources/Orders/Discount.swift"])

    navigator.changeFilter { $0.text = "" }
    #expect(navigator.listedFiles.count == 4)
  }

  @Test func neighborsOfAFileTheFilterLeavesOutAreTheListedOnesBesideItInTheGroups() {
    let navigator = CollectionNavigator(
      collection: FileCollection(files: Self.commit), showsIdenticalFiles: false)
    navigator.listFiles()
    _ = navigator.go(toFileAt: 2)

    navigator.changeFilter { $0.text = "readme" }
    #expect(navigator.shownRow == nil)
    #expect(navigator.neighborIndex(forward: false) == 1)
    #expect(navigator.neighborIndex(forward: true) == nil)

    navigator.changeFilter { $0.text = "tests" }
    #expect(navigator.neighborIndex(forward: false) == nil)
    #expect(navigator.neighborIndex(forward: true) == 3)
  }

  @Test func fileInViewThatWentGivesWayToTheFileAfterItInTheGroups() {
    let navigator = CollectionNavigator(
      collection: FileCollection(files: Self.commit), showsIdenticalFiles: false)
    navigator.listFiles()
    _ = navigator.go(toFileAt: 1)

    navigator.collection.take(.replaced([Self.commit[0], Self.commit[2], Self.commit[3]]))
    guard case .went(let next) = navigator.followShownFile() else {
      Issue.record("The file in view went")
      return
    }
    navigator.listFiles()

    #expect(
      navigator.listedIndex(from: next).map { navigator.collection.files[$0].path }
        == "Sources/Orders/OrderService.swift")
  }

  @Test func placeInAFileIsKeptByItsPath() {
    let navigator = navigator(showing: 0)
    let place = FilePlace(currentBlock: 2, row: 40, fraction: 0.5, lineArrangement: .aligned)

    navigator.keepPlace(place)
    _ = navigator.go(toFileAt: 2)

    #expect(navigator.place(of: Self.files[0]) == place)
    #expect(navigator.place(of: Self.file("a.txt", folder: "moved")) == place)
    #expect(navigator.place(of: Self.files[2]) == nil)
  }

  @Test func changesOfAFileWhoseSidesAreOtherFilesNowAreForgotten() async throws {
    let files = [Self.file("a.txt"), Self.file("c.txt"), Self.file("d.txt")]
    let navigator = CollectionNavigator(
      collection: FileCollection(files: files), showsIdenticalFiles: false)
    navigator.listFiles()
    let changes = { (file: CollectedFile, folder: String) async throws -> ChangedComparison in
      let side = { (url: URL) in SourceFile(bytes: Data("x\n".utf8), label: file.path, url: url) }
      let session = try await Session.diff(
        old: side(file.old.url), new: side(URL(filePath: "/tmp/\(folder)/\(file.path)")))
      return ChangedComparison(session: session, roles: [.b])
    }
    for (index, folder) in [(0, "new"), (1, "elsewhere")] {
      _ = navigator.go(toFileAt: index)
      navigator.keepChanges(try await changes(files[index], folder))
    }
    _ = navigator.go(toFileAt: 2)
    try #require(navigator.changedFiles.count == 2)

    #expect(navigator.forgetChangesOfFilesNoLongerCompared())

    #expect(Array(navigator.changedFiles.keys) == ["a.txt"])
    #expect(!navigator.forgetChangesOfFilesNoLongerCompared())
  }
}
