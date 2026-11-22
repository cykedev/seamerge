import Testing

@testable import SeamergeUI

/// How the list groups files by folder: the files at the top first, the folders in the order of
/// Git or by path, and filtered without the folders left empty.
struct FileGroupsTests {
  private static func folders(_ groups: FileGroups) -> [String] {
    groups.groups.map(\.folder)
  }

  @Test func inTheOrderOfGitEachFolderStandsWhereItsFirstFileStandsAndTheTopComesFirst() {
    let paths = [
      "Sources/Orders/OrderService.swift", "Tests/OrderTests.swift", "README.md",
      "Sources/Orders/Discount.swift", "prices.txt",
    ]

    let groups = FileGroups(paths: paths, folderOrder: .firstFile)

    #expect(Self.folders(groups) == ["", "Sources/Orders", "Tests"])
    #expect(groups.groups.map(\.members) == [[2, 4], [0, 3], [1]])
    #expect(groups.order == [2, 4, 0, 3, 1])
    #expect(groups.fileCount == 5)
  }

  @Test func inTheOrderOfGitAFolderMayFollowAFolderInIt() {
    let groups = FileGroups(paths: ["a/b/x.txt", "a/c.txt", "a/b/y.txt"], folderOrder: .firstFile)

    #expect(Self.folders(groups) == ["a/b", "a"])
    #expect(groups.order == [0, 2, 1])
  }

  @Test func byPathEachFolderComesBeforeTheFoldersInItAndTheTopComesFirst() {
    let paths = ["a/b/x.txt", "a/c.txt", "File10/z.txt", "File9/z.txt", "b.txt"]

    let groups = FileGroups(paths: paths, folderOrder: .path)

    #expect(Self.folders(groups) == ["", "a", "a/b", "File9", "File10"])
    #expect(groups.order == [4, 1, 0, 3, 2])
  }

  @Test func filterKeepsAFolderWhileOneOfItsFilesIsLeftAndDropsTheOthers() {
    let paths = ["README.md", "Sources/A.swift", "Sources/B.swift", "Tests/C.swift"]
    let groups = FileGroups(paths: paths, folderOrder: .firstFile)

    let filtered = groups.filter { [1, 3].contains($0) }

    #expect(Self.folders(filtered) == ["Sources", "Tests"])
    #expect(filtered.order == [1, 3])
    #expect(filtered.fileCount == 2)
    #expect(groups.filter { _ in false }.groups.isEmpty)
  }

  @Test func folderIsAllBeforeTheLastSlash() {
    #expect(FileGroups.folder(of: "README.md") == "")
    #expect(FileGroups.folder(of: "Sources/Orders/OrderService.swift") == "Sources/Orders")
    #expect(FileGroups.folder(of: "Fächer/Über.txt") == "Fächer")
  }

  @Test func noFilesMakeNoGroups() {
    let groups = FileGroups(paths: [], folderOrder: .path)

    #expect(groups.groups.isEmpty)
    #expect(groups.order.isEmpty)
  }
}
