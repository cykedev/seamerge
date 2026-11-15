import AppKit
import Testing

@testable import SeamergeUI

/// Draws the pictures of comparisons of folders: Compare Files with two folders, the window while
/// the folders are compared, and in the smallest window.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct FolderPicturesTests {
  @Test(arguments: Look.all)
  func compareFilesWithFoldersIsPictured(look: Look) throws {
    let folders = try SampleFolders(left: "Seamerge 0.2", right: "Seamerge 0.3")
    let fixture = try CompareFilesFixture(
      displayOptions: DisplayOptions(increasesContrast: look.increasesContrast))
    #expect(fixture.controller.fill(with: [folders.left, folders.right]))
    try picture(fixture, look: look, named: "folders-compare-files-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func compareFilesWithAFileAndAFolderIsPictured(look: Look) throws {
    let folders = try SampleFolders(left: "Seamerge 0.2", right: "Seamerge 0.3")
    try folders.write("Notes.txt", left: "notes\n", right: nil)
    let fixture = try CompareFilesFixture()
    #expect(
      fixture.controller.fill(with: [folders.left, folders.left.appending(path: "Notes.txt")]))
    try picture(fixture, look: look, named: "folders-compare-files-mixed-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func windowWithOnlyChangedFilesIsPictured(look: Look) async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    let collection = await FileCollection.compared(folders)
    try await Windows.picture(collection, look: look, named: "folders-changed-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func progressIsPictured(look: Look) async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    let comparer = FolderComparer(
      folders: folders.pair, linkFolder: folders.folder.appending(path: "links"))
    let collection = FileCollection(comparer: comparer)
    let files = comparer.pairs(at: "").map {
      comparer.file(for: $0, change: comparer.change(of: $0))
    }
    collection.take(.listed(files.filter { $0.change != .identical }, waiting: 4_993))
    try await Windows.picture(collection, look: look, named: "folders-progress-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func comparingWithoutAFileIsPictured(look: Look) async throws {
    let folders = try SampleFolders()
    let collection = FileCollection(
      comparer: FolderComparer(
        folders: folders.pair, linkFolder: folders.folder.appending(path: "links")))
    try await Windows.picture(collection, look: look, named: "folders-comparing-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func sameFilesArePictured(look: Look) async throws {
    let folders = try SampleFolders()
    try folders.write("README.md", left: "same\n", right: "same\n")
    let collection = await FileCollection.compared(folders)
    try await Windows.picture(collection, look: look, named: "folders-same-\(look.name)")
  }

  @Test func windowIsPicturedInTheSmallestSize() async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    let collection = await FileCollection.compared(folders)
    try await Windows.picture(collection, look: .light, size: nil, named: "folders-smallest-light")
  }

  @Test func windowIsPicturedWithoutColorAndWithReducedTransparency() async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    let collection = await FileCollection.compared(folders)
    for (name, options) in [
      ("without-color", DisplayOptions(differentiatesWithoutColor: true)),
      ("reduced-transparency", DisplayOptions(reducesTransparency: true)),
    ] {
      try await Windows.picture(
        collection, look: .light, options: options, named: "folders-\(name)-light")
    }
  }

  private func picture(_ fixture: CompareFilesFixture, look: Look, named name: String) throws {
    let window = fixture.window
    window.colorSpace = .sRGB
    window.appearance = look.appearance
    window.contentView?.layoutSubtreeIfNeeded()
    try Rendering.write(try Rendering.bitmap(of: window), named: name)
  }
}
