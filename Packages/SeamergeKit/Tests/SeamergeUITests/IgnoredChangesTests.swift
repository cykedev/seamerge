import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Show Ignored Changes: highlights the places where lines differ in a way that the comparison
/// mode ignores, in the panes side by side, valid only where there are such lines.
@MainActor
@Suite(.serialized) struct IgnoredChangesTests {
  static let old = """
    struct Order {
    \tlet id: Int
      let  total: Decimal
      var items: [Item] = []
    }

    """
  static let new = """
    struct Order {
        let id: Int
      let total: Decimal
      var items: [Item] = []
      var note = ""
    }

    """

  static func diff(mode: ComparisonMode = .ignoreWhitespaceAmount) async throws -> Session {
    try await SampleDiffs.diff(old: old, new: new, label: "Order.swift", mode: mode)
  }

  @Test func showingIgnoredChangesHighlightsTheirPlacesInBothPanesAndHidingThemAgainClears()
    async throws
  {
    let controller = try Windows.controller(for: try await Self.diff())
    defer { controller.window?.close() }
    let panes = controller.presentation.layout.sourcePanes.map(\.pane)
    #expect(panes.allSatisfy { $0.content.ignoredDifferencePlaces.isEmpty })
    #expect(controller.validateUserInterfaceItem(Self.item()))
    #expect(Self.item(validatedBy: controller).title == "Show Ignored Changes")

    controller.toggleIgnoredChanges(nil)

    let texts = panes.map { pane in
      pane.content.ignoredDifferencePlaces.map {
        (pane.content.text as NSString).substring(
          with: NSRange(location: $0.lowerBound, length: $0.count))
      }
    }
    #expect(texts == [["\t", "  "], ["    ", " "]])
    #expect(Self.item(validatedBy: controller).title == "Hide Ignored Changes")

    controller.toggleIgnoredChanges(nil)
    #expect(panes.allSatisfy { $0.content.ignoredDifferencePlaces.isEmpty })
  }

  @Test func placesFollowTheLinesWhenLinesAreNotAligned() async throws {
    let controller = try Windows.controller(for: try await Self.diff())
    defer { controller.window?.close() }
    controller.toggleIgnoredChanges(nil)
    controller.toggleLineAlignment(nil)
    let pane = try #require(controller.presentation.layout.sourcePanes.last?.pane)
    let text = pane.content.text as NSString

    #expect(
      pane.content.ignoredDifferencePlaces.map {
        text.substring(with: NSRange(location: $0.lowerBound, length: $0.count))
      } == ["    ", " "])
  }

  @Test func commandIsInvalidWhereTheComparisonIgnoresNothing() async throws {
    let controller = try Windows.controller(for: try await Self.diff(mode: .exact))
    defer { controller.window?.close() }

    #expect(!controller.validateUserInterfaceItem(Self.item()))
  }

  @Test func commandIsInvalidWhereLinesDifferOnlyInTheirLineEndings() async throws {
    let session = try await SampleDiffs.diff(
      old: "first\r\nsecond\r\n", new: "first\nsecond\n", label: "notes.txt",
      mode: .ignoreWhitespaceAmount)
    let controller = try Windows.controller(for: session)
    defer { controller.window?.close() }
    try #require(!IgnoredDifferences(in: session).isEmpty, "the lines differ")

    #expect(!controller.validateUserInterfaceItem(Self.item()))
  }

  private static func item() -> NSMenuItem {
    NSMenuItem(
      title: SessionCommand.toggleIgnoredChanges.title,
      action: SessionCommand.toggleIgnoredChanges.action, keyEquivalent: "")
  }

  private static func item(validatedBy controller: SessionWindowController) -> NSMenuItem {
    let item = item()
    _ = controller.validateUserInterfaceItem(item)
    return item
  }

  @Test(arguments: Look.all)
  func ignoredChangesArePicturedInEveryLook(look: Look) async throws {
    try Windows.picture(
      try await Self.diff(), context: SessionContext(), look: look,
      options: DisplayOptions(increasesContrast: look.increasesContrast),
      named: "ignored-changes-\(look.name)"
    ) { controller in
      controller.toggleIgnoredChanges(nil)
    }
  }

  @Test func ignoredChangesArePicturedWithoutColorAndTransparencyAndInTheSmallestWindow()
    async throws
  {
    for (size, name) in [
      (WindowMetrics.defaultContentSize, "ignored-changes-without-color-light"),
      (nil, "ignored-changes-smallest-light"),
    ] as [(CGSize?, String)] {
      try Windows.picture(
        try await Self.diff(), context: SessionContext(), look: .light,
        options: DisplayOptions(differentiatesWithoutColor: true, reducesTransparency: true),
        size: size, named: name
      ) { controller in
        controller.toggleIgnoredChanges(nil)
      }
    }
  }
}
