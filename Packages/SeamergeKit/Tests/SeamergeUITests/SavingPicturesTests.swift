import AppKit
import FolderCompareTestSupport
import Testing

@testable import FolderCompare
@testable import SeamergeUI

/// Draws the pictures of copied changes that are not saved: the window of two folders with the
/// header that says Edited and the dots in the list, and the sheet that asks whether to save.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct SavingPicturesTests {
  /// Copies every change of README.md and the first one of OrderService.swift to the right, and
  /// shows OrderService.swift.
  private static func copyChanges(
    in controller: SessionWindowController, of collection: FileCollection
  ) async throws {
    for (path, all) in [("README.md", true), ("Sources/Orders/OrderService.swift", false)] {
      let index = try #require(collection.files.firstIndex { $0.path == path })
      controller.showFile(at: index)
      await controller.fileLoad?.value
      controller.presentation.jump(to: 0)
      if all {
        controller.copyAllChangesToRight(nil)
      } else {
        controller.copyToRight(nil)
      }
      await controller.copying?.value
    }
    #expect(controller.collectionLayout?.fileList.changedPaths.count == 2)
  }

  /// Draws the window with copied changes in two files, in `look` with `options` at `size`.
  private static func picture(
    look: Look, options: DisplayOptions = DisplayOptions(),
    size: CGSize? = WindowMetrics.defaultContentSize, named name: String
  ) async throws {
    let folders = try SampleFolders(left: "Orders 1.0", right: "Orders 1.1")
    try folders.fillWithProject()
    let collection = await FileCollection.compared(folders)
    try await Windows.picture(collection, look: look, options: options, size: size, named: name) {
      controller in try await copyChanges(in: controller, of: collection)
    }
  }

  @Test(arguments: Look.all)
  func editedFilesArePicturedInEveryLook(look: Look) async throws {
    try await Self.picture(
      look: look, options: DisplayOptions(increasesContrast: look.increasesContrast),
      named: "saving-edited-\(look.name)")
  }

  @Test func editedFilesArePicturedWithoutColor() async throws {
    try await Self.picture(
      look: .light, options: DisplayOptions(differentiatesWithoutColor: true),
      named: "saving-edited-without-color-light")
  }

  @Test func editedFilesArePicturedWithReducedTransparency() async throws {
    try await Self.picture(
      look: .light, options: DisplayOptions(reducesTransparency: true),
      named: "saving-edited-reduced-transparency-light")
  }

  @Test func editedFilesArePicturedInTheSmallestWindow() async throws {
    try await Self.picture(look: .light, size: nil, named: "saving-edited-smallest-light")
  }

  /// The sheet draws in the colors of the system, which increased contrast of the app leaves
  /// alone.
  @Test(arguments: [Look.light, .dark])
  func sheetThatAsksWhetherToSaveIsPictured(look: Look) throws {
    for (names, suffix) in [
      (["OrderService.swift"], "one"),
      (["OrderService.swift", "README.md", "prices-and-discounts-for-every-region.json"], "three"),
    ] {
      let alert = SessionSheets.savingChangesAlert(to: names)
      try Rendering.write(
        try Rendering.bitmap(of: alert, in: look), named: "saving-sheet-\(suffix)-\(look.name)")
      #expect(alert.buttons.map(\.title) == ["Save", "Don’t Save", "Cancel"])
      #expect(alert.buttons[1].keyEquivalent == "d")
    }
  }
}
