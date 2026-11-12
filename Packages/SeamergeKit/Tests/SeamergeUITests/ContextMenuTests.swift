import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The context menus of the panes and their headers: exactly the entries that have an effect at
/// the place, none of the text view's own, and Copy for the selection or else the block.
@MainActor
@Suite struct ContextMenuTests {
  @Test func menuOfAChangedBlockAboveJumpsAndCopies() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let a = try #require(controller.layout.sourcePane(.a))
    let menu = try menu(of: a, inBlock: 4)
    #expect(entries(of: menu) == ["Next Conflict", "Next Change", "—", "Copy"])
    #expect(menu.items.allSatisfy { $0.keyEquivalent.isEmpty })
  }

  @Test func menuOfUnchangedTextAboveJumpsAndSelects() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let b = try #require(controller.layout.sourcePane(.b))
    let menu = try menu(of: b, at: 0)
    #expect(entries(of: menu) == ["Next Conflict", "—", "Copy (disabled)", "Select All"])
  }

  @Test func menuOfTheResultOffersCutCopyAndPasteDisabledWhereTheyHaveNoEffect() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let result = try controller.mergeResult
    let block = try #require(
      controller.presentation.changes.blocks.indices.first {
        controller.presentation.changes.blocks[$0].kind == .changedInA
      })
    #expect(
      entries(of: try menu(of: result, inBlock: block)) == [
        "Next Conflict", "Next Change", "—", "Cut (disabled)", "Copy", "Paste (disabled)",
      ])
    #expect(
      entries(of: try menu(of: result, at: 0)) == [
        "Next Conflict", "—", "Cut (disabled)", "Copy (disabled)", "Paste (disabled)",
        "Select All",
      ])
  }

  @Test func openConflictInTheResultHasNoTextToCopy() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
    let result = try controller.mergeResult
    let conflict = try #require(controller.presentation.navigation.firstOpenConflict)
    #expect(
      entries(of: try menu(of: result, inBlock: conflict)) == [
        "Next Change", "—", "Cut (disabled)", "Copy (disabled)", "Paste (disabled)",
      ])
  }

  @Test func menuLeavesOutJumpsThatGoNowhere() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let a = try #require(controller.layout.sourcePane(.a))
    let last = a.content.blocks.count - 1
    controller.presentation.jump(to: last)
    #expect(entries(of: try menu(of: a, inBlock: last)) == ["Copy"])
  }

  @Test func secondaryClickMakesTheBlockUnderThePointerCurrent() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let b = try #require(controller.layout.sourcePane(.b))
    _ = try menu(of: b, inBlock: 6)
    #expect(controller.presentation.currentBlock == 6)
    #expect(try controller.mergeResult.currentBlock == 6)
  }

  @Test func copyTakesTheSelectionOrElseTheLinesOfTheBlock() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let a = try #require(controller.layout.sourcePane(.a))
    let block = try copyItem(of: try menu(of: a, inBlock: 0))
    #expect(block.action == SessionCommand.copyBlock.action)
    try perform(block)
    #expect(controller.pasteboard.string(forType: .string) == "line 3 from A\n")

    // With a selection, Copy is the standard command of the text, which writes to the general
    // pasteboard; the test leaves that alone.
    a.documentView.setSelectedRange(NSRange(location: 0, length: 4))
    let selection = try copyItem(of: try menu(of: a, inBlock: 0))
    #expect(selection.action == #selector(NSText.copy(_:)))
    #expect(selection.target === a.documentView)
    #expect(selection.isEnabled)
  }

  @Test func copyBlockOfTheMainMenuCopiesTheCurrentBlockOfThePaneWithTheFocus() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let window = try #require(controller.window)
    let b = try #require(controller.layout.sourcePane(.b))
    window.makeFirstResponder(b.documentView)
    controller.presentation.jump(to: 1)
    #expect(controller.canPerform(.copyBlock))
    #expect(window.tryToPerform(SessionCommand.copyBlock.action, with: nil))
    #expect(controller.pasteboard.string(forType: .string) == "line 8 from B\n")
    // An open conflict in the result shows a preview, which is no text to copy.
    controller.enterTextMode()
    #expect(!controller.canPerform(.copyBlock))
  }

  @Test func headerOffersToCopyThePathAndShowTheFileInTheFinder() async throws {
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "SeamergeUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    var files: [String: SourceFile] = [:]
    for (name, text) in [("base", "one\n"), ("a", "one from A\n"), ("b", "one\ntwo\n")] {
      let url = folder.appending(path: "\(name).txt")
      try Data(text.utf8).write(to: url)
      files[name] = try SourceFile(contentsOf: url, label: "\(name).txt")
    }
    let resultURL = folder.appending(path: "result.txt")
    let session = try await Session.merge(
      base: files["base"], a: try #require(files["a"]), b: try #require(files["b"]))
    let workspace = WorkspaceRecorder()
    let controller = try Windows.controller(
      for: session, context: SessionContext(resultURL: resultURL), workspace: workspace)
    let sources = try #require(
      controller.layout.splitViewItems.first?.viewController as? NSSplitViewController)
    let header = try #require(
      sources.splitViewItems.last?.topAlignedAccessoryViewControllers.first?.view)
    let window = try #require(header.window)
    let event = try #require(
      NSEvent.mouseEvent(
        with: .rightMouseDown, location: header.convert(CGPoint(x: 40, y: 10), to: nil),
        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 1))
    let menu = try #require(header.menu(for: event))
    #expect(entries(of: menu) == ["Copy Path", "Show in Finder"])
    for item in menu.items {
      try perform(item)
    }
    let url = try #require(files["b"]?.url)
    #expect(controller.pasteboard.string(forType: .string) == url.path(percentEncoded: false))
    #expect(workspace.revealedURLs == [url])
    // The result is not written yet, so its file cannot be shown.
    let result = try #require(controller.headerMenu(for: nil))
    #expect(entries(of: result) == ["Copy Path"])
  }

  @Test func headerOfAFileThatWasNotReadFromDiskHasNoMenu() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    #expect(controller.headerMenu(for: .a) == nil)
    #expect(controller.headerMenu(for: nil) == nil)
  }

  /// The menu that a secondary click on the first row of `block` of `pane` opens.
  private func menu(of pane: PaneView, inBlock block: Int) throws -> NSMenu {
    try menu(of: pane, at: pane.content.blocks[block].rows.lowerBound)
  }

  /// The menu that a secondary click on `row` of `pane` opens, as the text view shows it.
  private func menu(of pane: PaneView, at row: Int) throws -> NSMenu {
    let textView = pane.documentView
    let window = try #require(textView.window)
    let point = CGPoint(
      x: 20, y: (CGFloat(pane.displayRow(ofRow: row)) + 0.5) * pane.theme.rowHeight)
    let event = try #require(
      NSEvent.mouseEvent(
        with: .rightMouseDown, location: textView.convert(point, to: nil), modifierFlags: [],
        timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
        clickCount: 1, pressure: 1))
    return try #require(textView.menu(for: event))
  }

  /// Sends the action of `item` to its target, as choosing it does.
  private func perform(_ item: NSMenuItem) throws {
    NSApplication.shared.sendAction(try #require(item.action), to: item.target, from: item)
  }

  private func copyItem(of menu: NSMenu) throws -> NSMenuItem {
    try #require(menu.items.first { $0.title == "Copy" })
  }

  /// The titles of the items of `menu`, a dash for a separator, and disabled items marked.
  private func entries(of menu: NSMenu) -> [String] {
    menu.items.map { item in
      item.isSeparatorItem ? "—" : item.title + (item.isEnabled ? "" : " (disabled)")
    }
  }
}
