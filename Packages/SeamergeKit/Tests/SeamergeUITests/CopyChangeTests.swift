import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Copying a change of a comparison to the side that may be written: the button at the seam,
/// the keys, the Compare menu and the context menu carry out the same action, which is valid
/// only where it has an effect, compares anew, goes on as the settings say, and is one step of
/// undo.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct CopyChangeTests {
  /// The bytes of the right file of the greeting after copying its change, the second block,
  /// to the right.
  private static func greetingCopiedToRight() async throws -> Data {
    let session = try await SampleDiffs.greeting()
    let block = try #require(SessionChanges(session: session).blocks.dropFirst().first)
    return try session.file(after: ChangeCopy(block: block, from: .a)).bytes
  }

  /// A window of the greeting on disk, both files writable, its change current.
  private func greetingWindow(
    context: SessionContext = SessionContext(), settings: UserSettings = .private(),
    undoManager: UndoManager = UndoManager(), prompts: PromptRecorder = PromptRecorder()
  ) async throws -> SessionWindowController {
    let controller = try Windows.controller(
      for: try await WritableComparisons.greeting(), context: context, prompts: prompts,
      undoManager: undoManager, settings: settings)
    controller.presentation.jump(to: 1)
    return controller
  }

  /// Waits until the copy that a command or a button began shows.
  private func untilCopied(_ controller: SessionWindowController) async {
    await controller.copying?.value
  }

  private func text(of role: Role, in controller: SessionWindowController) -> Data {
    role == .a
      ? controller.presentation.changes.session.inputs.a.bytes
      : controller.presentation.changes.session.inputs.b.bytes
  }

  /// The button at the seam that copies `block` in `direction`, once the seam is laid out.
  private func button(
    ofBlock block: Int, _ direction: PaneSeam.CopyDirection, in controller: SessionWindowController
  ) throws -> CopyChangeButton {
    let seam = try #require(controller.layout.seams.first)
    seam.layoutSubtreeIfNeeded()
    return try #require(seam.copyButtons.first { $0.block == block && $0.direction == direction })
  }

  @Test func clickKeyMenuAndContextMenuCopyTheSameWay() async throws {
    let expected = try await Self.greetingCopiedToRight()

    let menu = try await greetingWindow()
    NSApplication.shared.sendAction(SessionCommand.copyToRight.action, to: menu, from: nil)
    await untilCopied(menu)
    #expect(text(of: .b, in: menu) == expected)

    let keys = try await greetingWindow()
    let window = try #require(keys.window)
    window.makeFirstResponder(try #require(keys.layout.sourcePane(.a)).documentView)
    try press(SessionCommand.rightArrow, in: keys)
    await untilCopied(keys)
    #expect(text(of: .b, in: keys) == expected)

    let click = try await greetingWindow()
    click.presentation.setCurrentBlock(nil)
    let seam = try #require(click.layout.seams.first)
    let arrow = try button(ofBlock: 1, .toRight, in: click)
    let center = seam.convert(CGPoint(x: arrow.frame.midX, y: arrow.frame.midY), to: seam.superview)
    #expect(seam.hitTest(center) === arrow)
    #expect(seam.hitTest(CGPoint(x: center.x, y: center.y + 30)) == nil)
    arrow.performClick(nil)
    await untilCopied(click)
    #expect(text(of: .b, in: click) == expected)

    let context = try await greetingWindow()
    let pane = try #require(context.layout.sourcePane(.a))
    let item = try #require(
      context.contextMenu(
        for: PaneHit(row: pane.content.blocks[1].rows.lowerBound, block: 1), in: pane
      )
      .items.first)
    #expect(item.title == "Copy to Greeting.swift")
    NSApplication.shared.sendAction(try #require(item.action), to: item.target, from: item)
    await untilCopied(context)
    #expect(text(of: .b, in: context) == expected)
  }

  @Test func contextMenuNamesTheSidesItCopiesToAndOffersOnlyWhatHasAnEffect() async throws {
    let both = try await greetingWindow()
    let pane = try #require(both.layout.sourcePane(.b))
    let titles = both.contextMenu(for: PaneHit(row: 0, block: 1), in: pane).items.prefix(2)
      .map(\.title)
    #expect(titles == ["Copy to Greeting.swift", "Copy to Greeting-old.swift"])

    let git = try await greetingWindow(context: SampleDiffs.gitContext)
    let menu = git.contextMenu(for: PaneHit(row: 0, block: 1), in: pane)
    #expect(menu.items.filter { $0.title.hasPrefix("Copy to") }.count == 1)
  }

  @Test func commandsAreValidOnlyWhereTheyCopy() async throws {
    let git = try await greetingWindow(context: SampleDiffs.gitContext)
    #expect(git.canPerform(.copyToRight))
    #expect(git.canPerform(.copyAllChangesToRight))
    #expect(!git.canPerform(.copyToLeft))
    #expect(!git.canPerform(.copyAllChangesToLeft))
    git.presentation.setCurrentBlock(nil)
    #expect(!git.canPerform(.copyToRight))
    #expect(git.canPerform(.copyAllChangesToRight))

    // Files that were not read from disk cannot be written.
    let unwritten = try Windows.controller(for: try await SampleDiffs.greeting())
    unwritten.presentation.jump(to: 1)
    #expect(
      SessionCommand.allCases.filter { $0.copy != nil }.allSatisfy { !unwritten.canPerform($0) })
    #expect(unwritten.layout.seams.isEmpty)

    let merge = try Windows.controller(for: try await SampleMerges.manyBlocks())
    merge.presentation.jump(to: 1)
    #expect(SessionCommand.allCases.filter { $0.copy != nil }.allSatisfy { !merge.canPerform($0) })
  }

  @Test(arguments: [true, false])
  func filesThatCannotBeShownOrWereNotReadWholeTakeNoCopy(isBinary: Bool) async throws {
    // A file that is not valid text in any encoding counts as binary; one that cannot be read
    // has no text at all. Neither window shows lines, so nothing can be copied.
    let unavailable = SampleDiffs.unavailable(isBinary: isBinary)
    let controller = try Windows.controller(
      for: try await unavailable.emptySession(), unavailable: unavailable)
    #expect(controller.copyDirections.isEmpty)
    #expect(
      SessionCommand.allCases.filter { $0.copy != nil }.allSatisfy { !controller.canPerform($0) })
    #expect(controller.layout.seams.isEmpty)
  }

  @Test func sideArrowsCopyTowardTheSideTheyPointTo() async throws {
    let controller = try await greetingWindow()
    let window = try #require(controller.window)
    window.makeFirstResponder(try #require(controller.layout.sourcePane(.b)).documentView)
    let session = controller.presentation.changes.session
    let expected = try session.file(
      after: ChangeCopy(block: controller.presentation.changes.blocks[1], from: .b)
    ).bytes
    let right = text(of: .b, in: controller)
    try press(SessionCommand.leftArrow, in: controller)
    await untilCopied(controller)
    #expect(text(of: .b, in: controller) == right)
    #expect(text(of: .a, in: controller) == expected)
    #expect(
      Keys.of(.copyToRight, in: .diff) == Keys(SessionCommand.rightArrow, [.option, .command]))
    #expect(Keys.of(.copyToLeft, in: .diff) == Keys(SessionCommand.leftArrow, [.option, .command]))
    #expect(Keys.of(.copyToRight, in: .merge) == nil)
    #expect(Keys.of(.useA, in: .merge) == Keys("1", [.command]))
    #expect(Keys.of(.useB, in: .merge) == Keys("3", [.command]))
  }

  @Test func sideArrowsStillChooseASideInAMerge() async throws {
    let settings = UserSettings.private()
    settings.goesToNextChange = false
    let controller = try Windows.controller(
      for: try await SampleMerges.manyBlocks(), settings: settings)
    let window = try #require(controller.window)
    window.makeFirstResponder(try #require(controller.layout.sourcePane(.a)).documentView)
    let conflict = try #require(controller.presentation.navigation.firstOpenConflict)
    controller.presentation.jump(to: conflict)
    try press(SessionCommand.rightArrow, in: controller)
    #expect(controller.isSourceOn(.b) && !controller.isSourceOn(.a))
    #expect(controller.copying == nil)
  }

  @Test(arguments: [true, false])
  func copyGoesOnAsTheSettingSays(goesOn: Bool) async throws {
    let settings = UserSettings.private()
    settings.goesToNextChange = goesOn
    let controller = try await greetingWindow(settings: settings)
    controller.copyToRight(nil)
    await untilCopied(controller)
    #expect(controller.presentation.changes.blocks.count == 2)
    if goesOn {
      #expect(controller.presentation.currentBlock == 1)
    } else {
      #expect(controller.presentation.currentBlock == nil)
      #expect(controller.presentation.navigation.target(of: .nextChange) == 1)
      #expect(controller.presentation.navigation.target(of: .previousChange) == 0)
    }
  }

  @Test func nextChangeOutOfSightComesIntoViewAfterTheCopy() async throws {
    let controller = try Windows.controller(
      for: try await WritableComparisons.manyChanges(spacing: 60))
    let presentation = controller.presentation
    controller.showAllLines(nil)
    presentation.jump(to: 1)
    let b = try #require(controller.layout.sourcePane(.b))
    try #require(!b.showsWhole(rows: b.content.blocks[2].rows), "the next change is out of view")
    controller.copyToRight(nil)
    await untilCopied(controller)
    #expect(presentation.currentBlock == 1)
    #expect(b.showsWhole(rows: b.content.blocks[1].rows))
  }

  @Test func copyOfTheLastChangeLeavesNoChangeCurrent() async throws {
    let controller = try await greetingWindow()
    let presentation = controller.presentation
    presentation.jump(to: 2)
    controller.copyToRight(nil)
    await untilCopied(controller)
    #expect(presentation.changes.blocks.count == 2)
    #expect(presentation.currentBlock == nil)
    #expect(presentation.navigation.target(of: .previousChange) == 1)
    #expect(presentation.navigation.target(of: .nextChange) == nil)
  }

  @Test func buttonsTakeNoPressesWhileTheFilesAreComparedAnew() async throws {
    let controller = try await greetingWindow()
    let arrow = try button(ofBlock: 1, .toRight, in: controller)
    #expect(arrow.isEnabled)
    await controller.comparisonSwitcher.whileComparingAnew {
      #expect(!arrow.isEnabled)
      #expect(!controller.canPerform(.copyToRight))
    }
    #expect(arrow.isEnabled)
  }

  @Test func formerValueOfTheSettingStillHolds() {
    let defaults = UserDefaults.privateSuite()
    defaults.set(true, forKey: "StaysOnDecidedConflict")
    #expect(!UserSettings(defaults: defaults).goesToNextChange)
    let fresh = UserSettings.private()
    #expect(fresh.goesToNextChange)
  }

  @Test func copiedLinesHaveNoTintOfTheirOwn() async throws {
    let controller = try await greetingWindow()
    let presentation = controller.presentation
    let b = try #require(controller.layout.sourcePane(.b))
    let copiedLine = presentation.changes.blocks[1].lines(in: .b).lowerBound
    controller.copyToRight(nil)
    await untilCopied(controller)
    let gridRow = presentation.changes.session.rowLayout.row(ofLine: copiedLine, in: .b)
    let row = presentation.row(ofGridRow: gridRow, in: b)
    #expect(!b.content.blocks.contains { $0.rows.contains(row) })
    #expect(b.content.rowTints[row] == nil)
  }

  @Test func singleColumnHasNoButtonButTheCommands() async throws {
    let controller = try await greetingWindow()
    controller.showSingleColumn(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    for seam in controller.layout.seams {
      seam.layoutSubtreeIfNeeded()
      #expect(seam.copyButtons.isEmpty)
    }
    #expect(controller.canPerform(.copyToRight))
  }

  @Test func undoBringsBackTextBlocksCurrentBlockAndCollapsedRuns() async throws {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let controller = try Windows.controller(
      for: try await WritableComparisons.manyChanges(), undoManager: undoManager)
    let presentation = controller.presentation
    presentation.jump(to: 5)
    let run = try #require(presentation.collapsed.runs.dropFirst(3).first)
    presentation.collapsed.expand(run)
    presentation.showCollapsedRuns()
    let before = (
      a: text(of: .a, in: controller), b: text(of: .b, in: controller),
      blocks: presentation.changes.blocks.map(\.id), current: presentation.currentBlock,
      runs: presentation.collapsed.runs
    )

    undoManager.beginUndoGrouping()
    controller.copyToRight(nil)
    await untilCopied(controller)
    undoManager.endUndoGrouping()
    #expect(text(of: .b, in: controller) != before.b)
    #expect(undoManager.undoMenuItemTitle == "Undo Copy to Right")

    undoManager.undo()
    await controller.comparisonSwitcher.bringingBack?.value
    #expect(text(of: .a, in: controller) == before.a)
    #expect(text(of: .b, in: controller) == before.b)
    #expect(presentation.changes.blocks.map(\.id) == before.blocks)
    #expect(presentation.currentBlock == before.current)
    #expect(presentation.collapsed.runs == before.runs)
  }

  @Test func copyAllChangesIsOneStep() async throws {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let controller = try Windows.controller(
      for: try await WritableComparisons.everyKindOfChange(), undoManager: undoManager)
    let before = text(of: .b, in: controller)
    undoManager.beginUndoGrouping()
    controller.copyAllChangesToRight(nil)
    await untilCopied(controller)
    undoManager.endUndoGrouping()
    #expect(controller.presentation.changes.blocks.isEmpty)
    #expect(undoManager.undoMenuItemTitle == "Undo Copy All Changes to Right")
    undoManager.undo()
    await controller.comparisonSwitcher.bringingBack?.value
    #expect(text(of: .b, in: controller) == before)
    #expect(!undoManager.canUndo)
  }

  @Test func swapSidesTakesTheWritableSideAndItsButtonsAlong() async throws {
    let controller = try await greetingWindow(context: SampleDiffs.gitContext)
    let seam = try #require(controller.layout.seams.first)
    #expect(seam.copyDirections == [.toRight])
    controller.swapSides(nil)
    #expect(controller.canPerform(.copyToLeft))
    #expect(!controller.canPerform(.copyToRight))
    #expect(controller.layout.seams.first?.copyDirections == [.toLeft])
    let arrow = try button(ofBlock: 1, .toLeft, in: controller)
    #expect(arrow.accessibilityHelp()?.contains("Greeting.swift") == true)
  }

  @Test func seamIsThereOnlyWhereASideMayBeWritten() async throws {
    let unwritten = try Windows.controller(for: try await SampleDiffs.greeting())
    #expect(unwritten.layout.seams.isEmpty)

    let one = try await greetingWindow(context: SampleDiffs.gitContext)
    #expect(one.layout.seams.map(\.frame.width) == [Theme.seamWidth])

    let both = try await greetingWindow()
    #expect(both.layout.seams.map(\.frame.width) == [Theme.wideSeamWidth])
    #expect(both.layout.seams.first?.copyDirections == [.toRight, .toLeft])
  }

  @Test func buttonsAreNamedAndCopiesAreAnnounced() async throws {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let controller = try await greetingWindow(undoManager: undoManager)
    var announcements: [String] = []
    controller.presentation.announce = { announcements.append($0) }
    let arrow = try button(ofBlock: 1, .toRight, in: controller)
    #expect(arrow.accessibilityRole() == .button)
    #expect(arrow.accessibilityLabel() == "Copy Change 2 to Right")
    #expect(arrow.accessibilityHelp()?.contains("Greeting.swift") == true)
    #expect(arrow.toolTip == "Copy to the right (⌥⌘→)")
    #expect(arrow.accessibilityHelp()?.contains("here") == false)
    let bin = try button(ofBlock: 0, .toRight, in: controller)
    #expect(bin.removesLines)
    #expect(!arrow.removesLines)
    #expect(bin.accessibilityLabel() == "Remove Change 1 from Right")
    #expect(bin.accessibilityHelp() == "Removes these lines from Greeting.swift.")
    #expect(bin.toolTip == "Remove these lines on the right (⌥⌘→)")

    undoManager.beginUndoGrouping()
    controller.copyToRight(nil)
    await untilCopied(controller)
    undoManager.endUndoGrouping()
    #expect(announcements.last == "Copied to Greeting.swift. 2 Changes")
    undoManager.undo()
    await controller.comparisonSwitcher.bringingBack?.value
    #expect(announcements.last == "Change restored", "\(announcements)")
  }

  @Test func runWhereTheCopyWasStaysExpanded() async throws {
    let controller = try Windows.controller(for: try await WritableComparisons.manyChanges())
    let presentation = controller.presentation
    presentation.jump(to: 4)
    let rowsBefore = presentation.collapsed.runs.count
    controller.copyToRight(nil)
    await untilCopied(controller)
    // The copy joined two runs of unchanged lines around the copied block into one, which
    // stays expanded.
    #expect(presentation.collapsed.runs.count < rowsBefore)
    #expect(!presentation.collapsed.expandedRuns.isEmpty)
  }

  @Test func lineOfTheSideCopiedFromStaysAtTheReadingLine() async throws {
    let settings = UserSettings.private()
    settings.alignsLines = false
    let controller = try Windows.controller(
      for: try await WritableComparisons.everyKindOfChange(), settings: settings)
    let a = try #require(controller.layout.sourcePane(.a))
    controller.presentation.jump(to: 6)
    let before = a.rowAtReadingLine.row
    controller.copyToRight(nil)
    await untilCopied(controller)
    #expect(a.rowAtReadingLine.row == before)
  }
}
