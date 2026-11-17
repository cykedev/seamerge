import AppKit
import Testing

@testable import SeamergeUI

/// Draws the pictures of comparisons of folders: the sheet Compare Files with two folders, the window with
/// identical files listed, while the folders are compared, filtered, and in the smallest window.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct FolderPicturesTests {
  @Test(arguments: Look.all)
  func compareFilesWithFoldersIsPictured(look: Look) throws {
    let folders = try SampleFolders(left: "Seamerge 0.2", right: "Seamerge 0.3")
    let fixture = try WelcomeFixture(
      displayOptions: DisplayOptions(increasesContrast: look.increasesContrast))
    #expect(fixture.controller.fill(with: [folders.left, folders.right]))
    try picture(fixture, look: look, named: "folders-compare-files-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func compareFilesWithAFileAndAFolderIsPictured(look: Look) throws {
    let folders = try SampleFolders(left: "Seamerge 0.2", right: "Seamerge 0.3")
    try folders.write("Notes.txt", left: "notes\n", right: nil)
    let fixture = try WelcomeFixture()
    #expect(
      fixture.controller.fill(with: [folders.left, folders.left.appending(path: "Notes.txt")]))
    try picture(fixture, look: look, named: "folders-compare-files-mixed-\(look.name)")
  }

  @Test(arguments: Look.all)
  func windowWithIdenticalFilesIsPictured(look: Look) async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    let settings = UserSettings.private()
    settings.showsIdenticalFiles = true
    let collection = await FileCollection.compared(folders)
    try await Windows.picture(
      collection, look: look, options: DisplayOptions(increasesContrast: look.increasesContrast),
      settings: settings, named: "folders-identical-\(look.name)")
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

  @Test(arguments: [Look.light, .dark])
  func filterIsPicturedWithMatchesAndWithout(look: Look) async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    let collection = await FileCollection.compared(folders)
    for (text, name) in [("order", "matches"), ("invoice", "no-match")] {
      try await Windows.picture(
        collection, look: look, named: "folders-filter-\(name)-\(look.name)"
      ) {
        controller in
        let fileList = try #require(controller.collectionLayout?.fileList)
        fileList.filterField.stringValue = text
        controller.fileList(fileList, didChangeFilter: text)
      }
    }
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
    let settings = UserSettings.private()
    settings.showsIdenticalFiles = true
    let collection = await FileCollection.compared(folders)
    for (name, options) in [
      ("without-color", DisplayOptions(differentiatesWithoutColor: true)),
      ("reduced-transparency", DisplayOptions(reducesTransparency: true)),
    ] {
      try await Windows.picture(
        collection, look: .light, options: options, settings: settings,
        named: "folders-\(name)-light")
    }
  }

  private func picture(_ fixture: WelcomeFixture, look: Look, named name: String) throws {
    try fixture.picture(look: look, named: name)
  }
}
