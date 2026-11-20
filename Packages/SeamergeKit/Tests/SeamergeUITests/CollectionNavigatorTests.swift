import Foundation
import GitSupport
import MergeModel
import Testing

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

  @Test func placeInAFileIsKeptByItsPath() {
    let navigator = navigator(showing: 0)
    let place = FilePlace(currentBlock: 2, row: 40, fraction: 0.5, lineArrangement: .aligned)

    navigator.keepPlace(place)
    _ = navigator.go(toFileAt: 2)

    #expect(navigator.place(of: Self.files[0]) == place)
    #expect(navigator.place(of: Self.file("a.txt", folder: "moved")) == place)
    #expect(navigator.place(of: Self.files[2]) == nil)
  }
}
