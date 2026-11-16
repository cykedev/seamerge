import AppKit
import MergeModel
import Testing

@testable import PaneKit
@testable import SeamergeUI

/// The diff window with Connected Sides: each pane shows its file without filler rows,
/// a seam between them connects the changes, and the panes couple block by block at the reading
/// line; turning it on and off keeps the block, the insertion point and the selection.
@MainActor
@Suite struct ConnectedSidesTests {
  @Test func alignLinesTurnsTheGridIntoTheLinesOfEachFileWithASeamBetween() async throws {
    let controller = try await connectedWindow()
    let (a, b) = try panes(of: controller)
    #expect(controller.presentation.lineArrangement == .connected)
    #expect(!a.content.lineNumbers.contains(-1))
    #expect(!b.content.lineNumbers.contains(-1))
    #expect(a.content.marksBlocksWithoutRows && b.content.marksBlocksWithoutRows)
    let session = controller.presentation.changes.session
    #expect(a.content.lineNumbers.count == session.rowLayout.lineCount(in: .a))
    #expect(controller.layout.seams.count == 1)
    let seam = try #require(controller.layout.seams.first)
    #expect(seam.frame.width == Theme.seamWidth)
    let gap = b.convert(b.bounds, to: nil).minX - a.convert(a.bounds, to: nil).maxX
    #expect(gap == Theme.seamWidth)

    controller.showAlignedLines(nil)
    #expect(controller.presentation.lineArrangement == .aligned)
    #expect(controller.layout.seams.isEmpty)
    #expect(a.content.lineNumbers.contains(-1))
    #expect(a.content.lineNumbers.count == session.rowLayout.rowCount)
  }

  @Test func menuItemOfTheArrangementIsCheckedInAComparisonAndAMerge() async throws {
    let aligned = NSMenuItem(
      title: SessionCommand.showAlignedLines.title,
      action: SessionCommand.showAlignedLines.action, keyEquivalent: "a")
    let connected = NSMenuItem(
      title: SessionCommand.showConnectedSides.title,
      action: SessionCommand.showConnectedSides.action, keyEquivalent: "A")
    for session in [try await SampleDiffs.everyKindOfChange(), try await SampleMerges.helloWorld()]
    {
      let controller = try Windows.controller(for: session)
      #expect(controller.validateUserInterfaceItem(aligned) && aligned.state == .on)
      #expect(controller.validateUserInterfaceItem(connected) && connected.state == .off)
      controller.showConnectedSides(nil)
      #expect(!controller.presentation.alignsLines)
      #expect(controller.validateUserInterfaceItem(aligned) && aligned.state == .off)
      #expect(controller.validateUserInterfaceItem(connected) && connected.state == .on)
    }
    let alignedKey = try #require(SessionCommand.showAlignedLines.keyEquivalent(in: .diff))
    #expect(alignedKey.key == "a" && alignedKey.modifiers == [.option, .command])
    let connectedKey = try #require(SessionCommand.showConnectedSides.keyEquivalent(in: .diff))
    #expect(connectedKey.key == "a" && connectedKey.modifiers == [.shift, .option, .command])
  }

  @Test func toolbarChoiceFollowsAlignLinesInAComparisonAndAMerge() async throws {
    for session in [try await SampleDiffs.everyKindOfChange(), try await SampleMerges.helloWorld()]
    {
      let controller = try Windows.controller(for: session)
      let choice = try #require(
        controller.window?.toolbar?.items.first { $0.itemIdentifier == .lineArrangement }
          as? NSToolbarItemGroup)
      #expect(choice.selectedIndex == 0)
      controller.showConnectedSides(nil)
      #expect(!controller.presentation.alignsLines)
      #expect(choice.selectedIndex == 1)
      #expect(choice.action == #selector(SessionWindowController.chooseLineArrangement(_:)))
      choice.selectedIndex = 0
      controller.chooseLineArrangement(choice)
      #expect(controller.presentation.alignsLines)
    }
  }

  @Test func settingsDecideHowANewComparisonAndANewMergeStart() async throws {
    let settings = UserSettings.private()
    settings.alignsLines = false
    let comparison = try Windows.controller(
      for: try await SampleDiffs.everyKindOfChange(), settings: settings)
    #expect(!comparison.presentation.alignsLines)
    let merge = try Windows.controller(for: try await SampleMerges.helloWorld(), settings: settings)
    #expect(!merge.presentation.alignsLines)
    #expect(UserSettings(defaults: settings.defaults).alignsLines == false)
  }

  @Test(arguments: [(false, false), (true, false), (false, true), (true, true)])
  func panesScrolledByHandMoveSteadilyAndStandTogetherOnTheTrack(
    wraps: Bool, collapses: Bool
  ) async throws {
    let controller = try await connectedWindow(longLines: wraps)
    if wraps {
      controller.toggleLineWrapping(nil)
    }
    if !collapses {
      controller.showAllLines(nil)
    }
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let (a, b) = try panes(of: controller)
    let track = try #require(ScrollTrack(panes: [a, b]))
    for leader in [b, a] {
      let step = leader.rowHeight / 4
      var steps = 0
      for direction in [1.0, -1.0] {
        var places = [a.readingLinePlace, b.readingLinePlace]
        leader.textView.liveScrollDidStart()
        while steps < 20_000 {
          let origin = leader.documentView.visibleRect.origin
          leader.documentView.scroll(CGPoint(x: 0, y: origin.y + direction * step))
          let now = [a.readingLinePlace, b.readingLinePlace]
          let moves = zip(now, places).map { ($0 - $1) * direction }
          #expect(
            moves.allSatisfy { $0 >= -0.001 && $0 <= leader.rowHeight },
            "\(moves) at step \(steps), \(direction)")
          let positions = [
            track.trackPositions(ofPane: 0, atPlace: now[0]),
            track.trackPositions(ofPane: 1, atPlace: now[1]),
          ]
          // Panes at the top or the end of their texts may stand short of the track.
          if !now.indices.contains(where: { atAnEnd([a, b][$0]) }) {
            #expect(
              positions[0].lowerBound <= positions[1].upperBound + 0.5
                && positions[1].lowerBound <= positions[0].upperBound + 0.5,
              "the panes stand together on the track: \(positions)")
          }
          guard moves.contains(where: { $0 > 0.001 }) else { break }
          places = now
          steps += 1
        }
        leader.textView.liveScrollDidEnd()
      }
      #expect(steps > 200)
    }
  }

  @Test func panesScrolledByKeysAndTheOverviewBarStandTogetherOnTheTrack() async throws {
    let controller = try await connectedWindow()
    let (a, b) = try panes(of: controller)
    let window = try #require(controller.window)
    let track = try #require(ScrollTrack(panes: [a, b]))
    func expectTogether(_ context: String) {
      let places = [a.readingLinePlace, b.readingLinePlace]
      let positions = [
        track.trackPositions(ofPane: 0, atPlace: places[0]),
        track.trackPositions(ofPane: 1, atPlace: places[1]),
      ]
      guard !atAnEnd(a), !atAnEnd(b) else { return }
      #expect(
        positions[0].lowerBound <= positions[1].upperBound + 0.5
          && positions[1].lowerBound <= positions[0].upperBound + 0.5,
        "\(context): \(positions)")
    }
    for (pane, other) in [(a, b), (b, a)] {
      window.makeFirstResponder(pane.documentView)
      pane.documentView.setSelectedRange(NSRange(location: 0, length: 0))
      pane.documentView.scrollRangeToVisible(pane.documentView.selectedRange())
      var previous = [pane.readingLinePlace, other.readingLinePlace]
      for step in 0..<400 {
        pane.documentView.moveDown(nil)
        pane.documentView.scrollRangeToVisible(pane.documentView.selectedRange())
        let now = [pane.readingLinePlace, other.readingLinePlace]
        #expect(now[0] >= previous[0] && now[1] >= previous[1] - 0.001, "key \(step)")
        expectTogether("key \(step)")
        previous = now
      }
      for _ in 0..<20 {
        pane.documentView.pageUp(nil)
        expectTogether("page up")
      }
    }
    let bar = controller.presentation.sourcesOverviewBar
    for value in stride(from: 0.0, through: 1.0, by: 0.05) {
      bar.doubleValue = value
      bar.sendAction(bar.action, to: bar.target)
      expectTogether("overview bar at \(value)")
    }
  }

  @Test func windowOfSeveralFilesShowsTheNextFileFarDownWithOtherBlocks() async throws {
    let folder = try SampleCollections.folder()
    func lines(_ name: String, _ count: Int) -> String {
      (0..<count).map { "let \(name)\($0) = \($0)" }.joined(separator: "\n") + "\n"
    }
    let collection = FileCollection(files: [
      try SampleCollections.file(
        "Long.swift", old: lines("u", 300) + "gone\n" + lines("v", 300),
        new: lines("u", 300) + lines("v", 300) + "added\n", number: 1, count: 2, in: folder),
      try SampleCollections.file(
        "Short.swift", old: "a\nb\nc\n", new: "a\nB\nB2\nB3\nc\n", number: 2, count: 2,
        in: folder),
    ])
    let settings = UserSettings.private()
    settings.alignsLines = false
    let controller = try await Windows.controller(for: collection, settings: settings)
    let window = try #require(controller.window)
    let (a, b) = try panes(of: controller)
    #expect(a.content.blocks.count == 2)
    controller.showAllLines(nil)
    b.documentView.scroll(CGPoint(x: 0, y: b.documentView.frame.height))

    #expect(window.tryToPerform(SessionCommand.nextFile.action, with: nil))
    await controller.fileLoad?.value
    window.contentView?.layoutSubtreeIfNeeded()

    #expect(a.content.blocks.count == 1 && b.content.blocks.count == 1)
    #expect(a.content.lineNumbers.count == 3 && b.content.lineNumbers.count == 5)
    b.documentView.scroll(CGPoint(x: 0, y: 10))
    #expect(ScrollTrack(panes: [a, b]) != nil)
  }

  @Test(arguments: [false, true])
  func jumpBringsTheBlockToTheReadingLineOfBothPanes(wraps: Bool) async throws {
    let controller = try await connectedWindow(longLines: wraps)
    if wraps {
      controller.toggleLineWrapping(nil)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
    }
    let (a, b) = try panes(of: controller)
    let blocks = a.content.blocks.count
    var checked = 0
    for block in 2..<blocks {
      controller.presentation.jump(to: block)
      // Toward the end, a pane whose text ends sooner stops at its last row instead.
      guard !reachesItsEnd(a), !reachesItsEnd(b) else { continue }
      checked += 1
      let tops = [a, b].map { pane in
        let span = pane.verticalSpan(ofRows: pane.content.blocks[block].rows)
        return pane.convert(CGPoint(x: 0, y: span.lowerBound), from: pane.documentView).y
      }
      #expect(abs(tops[0] - tops[1]) <= 1, "block \(block): \(tops)")
      #expect(abs(tops[0] - readingLine(of: a)) <= 1, "block \(block) at the reading line")
    }
    #expect(checked > blocks - 8)
  }

  @Test func turningAlignLinesOnAndOffKeepsTheBlockAtTheReadingLine() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.everyKindOfChange())
    let (a, b) = try panes(of: controller)
    let session = controller.presentation.changes.session
    for block in [3, 7, 13, 22] {
      controller.presentation.jump(to: block)
      // A little into the block, so that its fraction counts too.
      a.documentView.scroll(
        CGPoint(x: 0, y: a.documentView.visibleRect.minY + a.theme.rowHeight * 1.5))
      let gridPlace = position(atReadingLineOf: a)

      controller.showConnectedSides(nil)
      #expect(controller.presentation.currentBlock == block)
      let mostLines = session.rowLayout.block(atRow: Int(gridPlace))
      let leader =
        mostLines.lines(in: .b).count >= mostLines.lines(in: .a).count ? (b, Role.b) : (a, .a)
      let gridAgain = ScrollMap(session: session, from: .grid, to: .lines(leader.1))
        .sourcePosition(at: position(atReadingLineOf: leader.0))
      #expect(abs(gridAgain - gridPlace) < 0.06, "block \(block): \(gridAgain) for \(gridPlace)")

      controller.showAlignedLines(nil)
      #expect(abs(position(atReadingLineOf: a) - gridPlace) < 0.06, "block \(block) back")
    }
  }

  @Test func turningAlignLinesOnAndOffKeepsABlockBoundaryAtTheReadingLine() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.everyKindOfChange())
    let (a, b) = try panes(of: controller)
    for block in [3, 7, 13, 22] {
      controller.presentation.jump(to: block)
      let gridPlace = position(atReadingLineOf: a)
      #expect(gridPlace == Double(a.content.blocks[block].rows.lowerBound))

      controller.showConnectedSides(nil)
      #expect(controller.presentation.currentBlock == block)
      let tops = [a, b].map { pane in
        let span = pane.verticalSpan(ofRows: pane.content.blocks[block].rows)
        return pane.convert(CGPoint(x: 0, y: span.lowerBound), from: pane.documentView).y
      }
      for top in tops {
        #expect(abs(top - readingLine(of: a)) <= 1, "block \(block): \(tops)")
      }

      controller.showAlignedLines(nil)
      #expect(abs(position(atReadingLineOf: a) - gridPlace) < 0.06, "block \(block) back")
    }
  }

  @Test(arguments: [false, true])
  func turningAlignLinesOnAndOffAtAnEndKeepsThePlaceWithinALine(atTheEnd: Bool) async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.everyKindOfChange())
    let (a, b) = try panes(of: controller)
    a.documentView.scroll(CGPoint(x: 0, y: atTheEnd ? a.documentView.frame.height : 0))
    #expect(atAnEnd(a))
    let gridPlace = position(atReadingLineOf: a)

    controller.showConnectedSides(nil)
    // At the end, the side with fewer lines stops before the other.
    #expect(atAnEnd(a) || atAnEnd(b))
    controller.showAlignedLines(nil)
    let placeAgain = position(atReadingLineOf: a)
    #expect(abs(placeAgain - gridPlace) <= 1, "\(gridPlace) became \(placeAgain)")
  }

  /// Where both sides show their tops, so does the grid, even though each side's reading line
  /// lies below lines that only the other side has, further down the grid than on either side.
  @Test func turningAlignLinesOffAndOnAtTheTopShowsTheTopOfTheGrid() async throws {
    // A change every few lines, so that no run of unchanged lines collapses.
    let lines = (1...200).map { "line \($0)" }
    let changed = lines.enumerated().map {
      $0.offset % 6 == 5 ? $0.element + " changed" : $0.element
    }
    let old = (["only old 1", "only old 2", "only old 3"] + lines).joined(separator: "\n")
    let new = ([changed[0], "only new 1", "only new 2", "only new 3"] + changed.dropFirst())
      .joined(separator: "\n")
    let controller = try Windows.controller(
      for: try await SampleDiffs.diff(old: old, new: new, label: "lines.txt"))
    let (a, b) = try panes(of: controller)
    controller.showConnectedSides(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    a.documentView.scroll(.zero)
    #expect(a.documentView.visibleRect.minY <= 0 && b.documentView.visibleRect.minY <= 0)

    controller.showAlignedLines(nil)
    #expect(a.documentView.visibleRect.minY <= 0, "\(a.documentView.visibleRect.minY)")
  }

  @Test func turningAlignLinesOnAndOffKeepsTheInsertionPointAndTheSelection() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.everyKindOfChange())
    let (a, b) = try panes(of: controller)
    let window = try #require(controller.window)
    controller.presentation.jump(to: 5)
    window.makeFirstResponder(b.documentView)
    let row = b.content.blocks[5].rows.lowerBound + 1
    let text = b.documentView.string as NSString
    let line = text.lineRange(for: NSRange(location: offset(ofRow: row, in: text), length: 0))
    let selection = NSRange(location: line.location + 4, length: line.length + 6)
    b.documentView.setSelectedRange(selection)
    let selected = text.substring(with: selection)
    a.documentView.setSelectedRange(NSRange(location: 17, length: 0))

    for command in [SessionCommand.showConnectedSides, .showAlignedLines] {
      controller.perform(command)
      let range = b.documentView.selectedRange()
      #expect((b.documentView.string as NSString).substring(with: range) == selected)
      #expect(window.firstResponder === b.documentView)
      #expect(a.documentView.selectedRange() == NSRange(location: 17, length: 0))
      #expect(controller.presentation.currentBlock == 5)
    }
  }

  @Test func expandedRunsStayExpandedAcrossTheSwitch() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.manyChanges())
    let (a, _) = try panes(of: controller)
    let run = try #require(a.collapsedRuns.first)
    controller.presentation.pane(a, didAskToExpand: run)
    let collapsed = controller.presentation.collapsed.runs
    controller.showConnectedSides(nil)
    #expect(controller.presentation.collapsed.runs == collapsed)
    #expect(a.collapsedRuns.count == collapsed.count)
  }

  @Test func goToLinePutsTheLineOfThePaneAtItsReadingLine() async throws {
    let controller = try await connectedWindow()
    let (a, b) = try panes(of: controller)
    for (pane, line) in [(b, 120), (a, 60)] {
      let row = controller.presentation.go(toLine: line, in: pane)
      #expect(row == line)
      #expect(pane.rowAtReadingLine.row == line)
    }
  }

  @Test func swapSidesMirrorsTheBandsAndKeepsTheLinesOfEachFile() async throws {
    let controller = try await connectedWindow()
    let (a, _) = try panes(of: controller)
    let leftLines = a.content.lineNumbers.count
    controller.swapSides(nil)
    let (left, right) = (
      controller.layout.sourcePanes[0].pane, controller.layout.sourcePanes[1].pane
    )
    let session = controller.presentation.changes.session
    #expect(left.content.lineNumbers.count == session.rowLayout.lineCount(in: .b))
    #expect(right.content.lineNumbers.count == leftLines)
    let seam = try #require(controller.layout.seams.first)
    #expect(seam.leftPane === left && seam.rightPane === right)
    // The removal reads as an insertion now: its rows are on the right.
    let removal = try #require(left.content.blocks.firstIndex { $0.rows.isEmpty })
    #expect(!right.content.blocks[removal].rows.isEmpty)
  }

  @Test func copyingABlockTakesTheLinesOfThePane() async throws {
    let controller = try await connectedWindow()
    let (a, _) = try panes(of: controller)
    let block = try #require(a.content.blocks.firstIndex { $0.rows.count == 4 })
    let copied = controller.blockText(at: CopiedPlace(pane: a, block: block))
    #expect(copied.split(separator: "\n").allSatisfy { $0.contains("removed") })
    #expect(copied.split(separator: "\n").count == 4)
    let empty = try #require(a.content.blocks.firstIndex { $0.rows.isEmpty })
    #expect(controller.blockText(at: CopiedPlace(pane: a, block: empty)).isEmpty)
  }

  @Test func overviewBarKeepsItsMarksAndMeasuresTheVisiblePartOnTheGrid() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.everyKindOfChange())
    let bar = controller.presentation.sourcesOverviewBar
    let marks = bar.marks
    controller.showConnectedSides(nil)
    #expect(bar.marks == marks)
    let (_, b) = try panes(of: controller)
    b.documentView.scroll(CGPoint(x: 0, y: b.documentView.frame.height))
    #expect(bar.doubleValue > 0.99)
    b.documentView.scroll(.zero)
    #expect(bar.doubleValue < 0.01)
  }

  @Test func windowIsWiderAtLeastByTheSeam() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.everyKindOfChange())
    let aligned = controller.layout.minimumWidth
    controller.showConnectedSides(nil)
    #expect(controller.layout.minimumWidth >= aligned + Theme.seamWidth - 1)
  }

  @Test func emptyFileShowsAHairlineWhereTheLinesOfTheOtherSideAreMissing() async throws {
    let controller = try Windows.controller(
      for: try await SampleDiffs.diff(old: "", new: "first\nsecond\n"))
    controller.showConnectedSides(nil)
    let (a, b) = try panes(of: controller)
    #expect(a.content.text.isEmpty)
    #expect(a.content.blocks.map(\.rows) == [0..<0])
    #expect(b.content.blocks.map(\.rows) == [0..<2])
    let band = try #require(controller.layout.seams.first?.bands.first)
    #expect(band.left.lowerBound == band.left.upperBound)
    #expect(band.right.upperBound - band.right.lowerBound > b.theme.rowHeight)
  }

  /// A window of ``SampleDiffs/everyKindOfChange(repeats:longLines:)`` with Connected Sides.
  private func connectedWindow(longLines: Bool = false) async throws -> SessionWindowController {
    let controller = try Windows.controller(
      for: try await SampleDiffs.everyKindOfChange(repeats: 16, longLines: longLines))
    controller.showConnectedSides(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    return controller
  }

  private func panes(of controller: SessionWindowController) throws -> (PaneView, PaneView) {
    (
      try #require(controller.layout.sourcePane(.a)),
      try #require(controller.layout.sourcePane(.b))
    )
  }

  /// The row of `pane` at its reading line, with the fraction the reading line passes down it.
  private func position(atReadingLineOf pane: PaneView) -> Double {
    let (row, fraction) = pane.rowAtReadingLine
    return Double(row) + Double(fraction)
  }

  /// Whether `pane` stands at the top or the end of its text.
  private func atAnEnd(_ pane: PaneView) -> Bool {
    pane.documentView.visibleRect.minY <= 0 || reachesItsEnd(pane)
  }

  private func reachesItsEnd(_ pane: PaneView) -> Bool {
    let text = pane.documentView
    return text.visibleRect.maxY >= text.frame.height - 1
  }

  private func readingLine(of pane: PaneView) -> CGFloat {
    let visible = pane.documentView.visibleRect
    return pane.convert(
      CGPoint(x: 0, y: visible.minY + visible.height * Theme.readingLine), from: pane.documentView
    ).y
  }

  /// The UTF-16 offset at which `row` of `text` starts.
  private func offset(ofRow row: Int, in text: NSString) -> Int {
    var offset = 0
    for _ in 0..<row {
      offset = NSMaxRange(text.lineRange(for: NSRange(location: offset, length: 0)))
    }
    return offset
  }
}
