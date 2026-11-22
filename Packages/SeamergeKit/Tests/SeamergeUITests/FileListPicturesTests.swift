import AppKit
import FolderCompareTestSupport
import GitSupport
import MergeModel
import PaneKit
import Testing

@testable import FolderCompare
@testable import SeamergeUI

/// Draws the list of files grouped by folder: a comparison of two versions of a project with
/// files at the top and in deep folders, every state, unsaved changes, at the standard width of
/// the sidebar and at the widest, in every look, filtered and scrolled.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct FileListPicturesTests {
  private static let paths = [
    "CHANGELOG.md", "README.md", ".swift-format",
    "App/Seamerge/AppDelegate+Service.swift", "App/Seamerge/AppDelegate.swift",
    "App/Seamerge/AppPresenter.swift", "App/SeamergeTests/Support/AppSandbox.swift",
    "Documentation/Images/connected-dark.png", "Documentation/Images/collection-dark.png",
    "Packages/MergeEngine/Sources/CMergeEngine/Adapter/Adapter.cc",
    "Packages/SeamergeKit/Sources/FolderCompare/CollectedFile.swift",
    "Packages/SeamergeKit/Sources/FolderCompare/CollectionCache.swift",
    "Packages/SeamergeKit/Sources/FolderCompare/CollectionCacheError.swift",
    "Packages/SeamergeKit/Sources/PaneKit/BlockDecision.swift",
    "Packages/SeamergeKit/Sources/PaneKit/CollapsedRunBar.swift",
    "Packages/SeamergeKit/Sources/PaneKit/ColorRole.swift",
    "Packages/SeamergeKit/Sources/PaneKit/CopyChangeButton.swift",
    "Packages/SeamergeKit/Sources/SeamergeUI/BlockHighlights.swift",
    "Packages/SeamergeKit/Sources/SeamergeUI/BuiltInIgnoreRule.swift",
    "Packages/SeamergeKit/Sources/SeamergeUI/CollectedFile+Presentation.swift",
    "Packages/SeamergeKit/Sources/SeamergeUI/CollectionNavigator.swift",
    "Packages/SeamergeKit/Sources/SeamergeUI/FileListViewController.swift",
    "Packages/SeamergeKit/Sources/SeamergeUI/SessionWindowController+ChangedFiles.swift",
    "Packages/SeamergeKit/Sources/SeamergeUI/SessionWindowController+Collection.swift",
    "Packages/SeamergeKit/Sources/SeamergeUI/WindowMetrics.swift",
    "Packages/SeamergeKit/Tests/SeamergeUITests/CollectionWindowTests.swift",
    "Packages/SeamergeKit/Tests/SeamergeUITests/FileListTests.swift",
    "Packages/SeamergeKit/Tests/SeamergeUITests/FolderWindowTests.swift",
    "Scripts/check.sh", "Scripts/format-strings.sh",
  ]

  private static let changes: [String: CollectedFile.Change] = [
    ".swift-format": .identical,
    "App/Seamerge/AppPresenter.swift": .added,
    "Documentation/Images/connected-dark.png": .deleted,
    "Documentation/Images/collection-dark.png": .unreadable(reason: "You don’t have permission."),
    "Packages/SeamergeKit/Sources/FolderCompare/CollectionCacheError.swift": .identical,
    "Packages/SeamergeKit/Sources/PaneKit/ColorRole.swift": .identical,
    "Packages/SeamergeKit/Sources/PaneKit/CopyChangeButton.swift": .added,
    "Packages/SeamergeKit/Sources/SeamergeUI/BuiltInIgnoreRule.swift": .deleted,
  ]

  private static let edited: Set<String> = [
    "Packages/SeamergeKit/Sources/FolderCompare/CollectedFile.swift",
    "Packages/SeamergeKit/Sources/PaneKit/CollapsedRunBar.swift",
    "Packages/SeamergeKit/Sources/SeamergeUI/CollectedFile+Presentation.swift",
  ]

  private static let selected = "Packages/SeamergeKit/Sources/PaneKit/CollapsedRunBar.swift"

  /// The files of two versions of a project, sorted by path as a comparison of folders sorts
  /// them; they share their sides on disk.
  private static func collection() throws -> FileCollection {
    let first = try SampleCollections.file(
      "CHANGELOG.md", old: SampleCollections.orderOld, new: SampleCollections.orderNew,
      in: try SampleCollections.folder())
    let files = paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map {
      path in
      var old = first.old
      var new = first.new
      old.label = path
      new.label = path
      return CollectedFile(
        old: old, new: new, difftool: DifftoolContext(path: path),
        change: changes[path] ?? .modified)
    }
    return FileCollection(files: files)
  }

  /// Draws the window of the project in `look` with `options`, the sidebar `sidebarWidth` wide,
  /// after `prepare`.
  private func picture(
    look: Look, options: DisplayOptions? = nil, sidebarWidth: CGFloat? = nil,
    named name: String,
    prepare: @MainActor (SessionWindowController) async throws -> Void = { _ in }
  ) async throws {
    let collection = try Self.collection()
    let settings = UserSettings.private()
    settings.showsIdenticalFiles = true
    try await Windows.picture(
      collection, look: look,
      options: options ?? DisplayOptions(increasesContrast: look.increasesContrast),
      settings: settings, named: name
    ) { controller in
      let layout = try #require(controller.collectionLayout)
      if let sidebarWidth {
        layout.splitView.setPosition(sidebarWidth, ofDividerAt: 0)
        layout.splitView.layoutSubtreeIfNeeded()
      }
      let index = try #require(collection.files.firstIndex { $0.path == Self.selected })
      controller.showFile(at: index)
      await controller.fileLoad?.value
      layout.fileList.changedPaths = Self.edited
      try await prepare(controller)
    }
  }

  @Test(arguments: Look.all)
  func listIsPicturedAtTheStandardWidth(look: Look) async throws {
    try await picture(look: look, named: "list-220-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func listIsPicturedAtTheWidestWidth(look: Look) async throws {
    try await picture(
      look: look, sidebarWidth: WindowMetrics.maximumSidebarWidth,
      named: "list-widest-\(look.name)")
  }

  @Test func listIsPicturedWithoutColorAndWithReducedTransparency() async throws {
    try await picture(
      look: .light, options: DisplayOptions(differentiatesWithoutColor: true),
      named: "list-without-color-light")
    try await picture(
      look: .light, options: DisplayOptions(reducesTransparency: true),
      named: "list-reduced-transparency-light")
  }

  @Test func filteredListIsPictured() async throws {
    try await picture(look: .light, named: "list-filter-light") { controller in
      let fileList = try #require(controller.collectionLayout?.fileList)
      fileList.filterField.stringValue = "window"
      controller.fileList(fileList, didChangeFilter: "window")
    }
  }

  @Test(arguments: [Look.light, .dark])
  func scrolledListIsPicturedWithTheHeadingStandingAtTheTop(look: Look) async throws {
    try await picture(look: look, named: "list-scrolled-\(look.name)") { controller in
      let table = try #require(controller.collectionLayout?.fileList.tableView)
      // Halfway into the files of a folder, so that its heading stands above them; the list
      // begins below the title bar.
      let inset = table.enclosingScrollView?.contentInsets.top ?? 0
      table.scroll(CGPoint(x: 0, y: table.rect(ofRow: 24).minY - inset))
    }
  }

  @Test func listIsPicturedInTheSmallestWindow() async throws {
    let collection = try Self.collection()
    try await Windows.picture(collection, look: .light, size: nil, named: "list-smallest-light")
  }
}
