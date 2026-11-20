import AppKit
import FolderCompareTestSupport
import PaneKit
import Testing

@testable import FolderCompare
@testable import SeamergeUI

/// Draws the pictures of the window that compares several files: a commit of a few files and of
/// a thousand, while files still come, and in the smallest window.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct CollectionPicturesTests {
  @Test(arguments: Look.all)
  func commitIsPicturedInEveryLook(look: Look) async throws {
    let collection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    try await Windows.picture(
      collection, look: look, options: DisplayOptions(increasesContrast: look.increasesContrast),
      named: "collection-commit-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func thousandFilesArePictured(look: Look) async throws {
    let collection = FileCollection(
      files: try SampleCollections.many(1000, in: try SampleCollections.folder()))
    try await Windows.picture(collection, look: look, named: "collection-1000-\(look.name)") {
      controller in
      controller.showFile(at: 499)
      await controller.fileLoad?.value
    }
  }

  @Test(arguments: [Look.light, .dark])
  func receivingIsPictured(look: Look) async throws {
    let files = try SampleCollections.many(40, in: try SampleCollections.folder())
    let collection = FileCollection(
      origin: CollectionOrigin(repository: "/repository", run: nil), expectedCount: 40,
      quietPeriod: .seconds(60))
    for file in files.prefix(12) {
      collection.add(file)
    }
    try await Windows.picture(collection, look: look, named: "collection-receiving-\(look.name)")
  }

  @Test func commitIsPicturedWithoutColor() async throws {
    let collection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    try await Windows.picture(
      collection, look: .light, options: DisplayOptions(differentiatesWithoutColor: true),
      named: "collection-without-color-light")
  }

  @Test func commitIsPicturedWithReducedTransparency() async throws {
    let collection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    try await Windows.picture(
      collection, look: .light, options: DisplayOptions(reducesTransparency: true),
      named: "collection-reduced-transparency-light")
  }

  @Test func commitIsPicturedInTheSmallestWindow() async throws {
    let collection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    try await Windows.picture(
      collection, look: .light, size: nil, named: "collection-smallest-light")
  }

  /// The signs of the list reach 3 : 1 and the folders 4.5 : 1, on the window background and on
  /// the selection; the glass of the sidebar lets the window background through.
  @Test(arguments: Look.all)
  func signsAndFoldersAreLegibleInTheList(look: Look) throws {
    let options = DisplayOptions(increasesContrast: look.increasesContrast)
    let theme = options.theme(settings: .private(), fontSize: 13)
    let window = try #require(Contrast.resolve(.windowBackgroundColor, in: look.appearance))
    let selection = Contrast.over(
      Contrast.resolve(.unemphasizedSelectedContentBackgroundColor, in: look.appearance), window)
    let folder = Contrast.resolve(CompareFilesColors(options).quietText, in: look.appearance)
    let signs = [
      CollectedFile.Change.modified, .added, .deleted, .identical, .unreadable(reason: ""),
    ].map {
      Contrast.resolve($0.presentation.color(in: theme), in: look.appearance)
    }

    for background in [window, selection] {
      let folderRatio = Contrast.ratio(Contrast.over(folder, background), background)
      #expect(folderRatio >= 4.5, "folder \(folderRatio)")
      for sign in signs {
        let ratio = Contrast.ratio(Contrast.over(sign, background), background)
        #expect(ratio >= 3, "sign \(ratio)")
      }
    }
  }
}
