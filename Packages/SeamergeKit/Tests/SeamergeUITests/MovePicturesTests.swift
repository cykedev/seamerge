import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Draws the pictures of moved lines for the visual review: a function moved down in a
/// comparison, at its new place and at its old one, in every look, without color, in the
/// smallest window, as the current block, with connected sides, and in a merge.
@MainActor
@Suite(.serialized) struct MovePicturesTests {
  @Test(arguments: Look.all)
  func moveIsPicturedAtBothEndsInEveryLook(look: Look) async throws {
    let session = try await MoveSamples.movedDown()
    try Windows.picture(
      session, context: SessionContext(), look: look,
      options: DisplayOptions(increasesContrast: look.increasesContrast), size: Self.size,
      named: "move-\(look.name)"
    ) { controller in
      controller.presentation.setCurrentBlock(nil)
    }
  }

  @Test(arguments: [Look.light, .dark])
  func moveIsPicturedWithoutColor(look: Look) async throws {
    try Windows.picture(
      try await MoveSamples.movedDown(), context: SessionContext(), look: look,
      options: DisplayOptions(differentiatesWithoutColor: true), size: Self.size,
      named: "move-without-color-\(look.name)"
    ) { controller in
      controller.presentation.setCurrentBlock(nil)
    }
  }

  @Test func moveIsPicturedInTheSmallestWindow() async throws {
    try Windows.picture(
      try await MoveSamples.movedDown(), context: SessionContext(), look: .light, size: nil,
      named: "move-smallest-light")
  }

  /// Pictures the place the lines left as the current block, in the key window with the focus
  /// in its pane, where the arrow takes the color of selected content, and without it.
  @Test(arguments: [Look.light, .dark], [false, true])
  func endIsPicturedAsTheCurrentBlock(look: Look, isFocused: Bool) async throws {
    try Windows.picture(
      try await MoveSamples.movedDown(), context: SessionContext(), look: look,
      actsAsKey: isFocused, size: Self.size,
      named: "move-current\(isFocused ? "-focused" : "")-\(look.name)"
    ) { controller in
      let a = controller.layout.sourcePanes[0].pane
      if let source = a.content.blocks.firstIndex(where: { $0.move != nil }) {
        controller.presentation.setCurrentBlock(source)
      }
      if isFocused {
        controller.window?.makeFirstResponder(a.documentView)
      }
    }
  }

  @Test(arguments: [Look.light, .dark])
  func moveIsPicturedWithConnectedSides(look: Look) async throws {
    let settings = UserSettings.private()
    settings.alignsLines = false
    try Windows.picture(
      try await MoveSamples.movedDown(), context: SessionContext(), look: look,
      settings: settings, size: Self.size, named: "move-connected-\(look.name)"
    ) { controller in
      controller.presentation.setCurrentBlock(nil)
    }
  }

  @Test(arguments: [Look.light, .dark])
  func moveIsPicturedInAMerge(look: Look) async throws {
    try Windows.picture(
      try await MoveSamples.movedInA(), context: SessionContext(), look: look,
      size: CGSize(width: 1280, height: 860), named: "move-merge-\(look.name)")
  }

  /// The size of the pictures, which shows all of the sample.
  private static let size = CGSize(width: 1280, height: 560)
}
