import AppKit
import MergeModel
import Testing

@testable import PaneKit
@testable import SeamergeUI

/// The diff window with Align Lines turned off: each pane shows its file without filler rows,
/// a seam between them connects the changes, and the panes couple block by block at the reading
/// line; turning it on and off keeps the block, the insertion point and the selection.
@MainActor
@Suite struct ConnectedSidesTests {
  @Test func alignLinesTurnsTheGridIntoTheLinesOfEachFileWithASeamBetween() async throws {
    let controller = try await connectedWindow()
    let (a, b) = try panes(of: controller)
    #expect(!controller.isSwitchedOn(.toggleLineAlignment))
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

    controller.toggleLineAlignment(nil)
    #expect(controller.isSwitchedOn(.toggleLineAlignment))
    #expect(controller.layout.seams.isEmpty)
    #expect(a.content.lineNumbers.contains(-1))
    #expect(a.content.lineNumbers.count == session.rowLayout.rowCount)
  }

  @Test func menuItemIsCheckedWhileLinesLineUpInAComparisonAndAMerge() async throws {
    let item = NSMenuItem(
      title: SessionCommand.toggleLineAlignment.title,
      action: SessionCommand.toggleLineAlignment.action, keyEquivalent: "a")
    let comparison = try Windows.controller(for: try await SampleDiffs.everyKindOfChange())
    #expect(comparison.validateUserInterfaceItem(item))
    #expect(item.state == .on)
    comparison.toggleLineAlignment(nil)
    #expect(comparison.validateUserInterfaceItem(item))
    #expect(item.state == .off)

    let merge = try Windows.controller(for: try await SampleMerges.helloWorld())
    #expect(merge.validateUserInterfaceItem(item))
    #expect(item.state == .on)
    merge.toggleLineAlignment(nil)
    #expect(!merge.presentation.alignsLines)
    #expect(merge.validateUserInterfaceItem(item))
    #expect(item.state == .off)
    let key = try #require(SessionCommand.toggleLineAlignment.keyEquivalent(in: .diff))
    #expect(key.key == "a" && key.modifiers == [.option, .command])
  }

  @Test func footerToggleFollowsAlignLinesInAComparisonAndAMerge() async throws {
    let comparison = try Windows.controller(for: try await SampleDiffs.everyKindOfChange())
    let button = try #require(comparison.content.footer.button(of: .lineAlignment))
    #expect(button.state == .on)
    #expect(NSApp.sendAction(try #require(button.action), to: comparison, from: button))
    #expect(!comparison.presentation.alignsLines)
    #expect(button.state == .off)

    let merge = try Windows.controller(for: try await SampleMerges.helloWorld())
    let mergeButton = try #require(merge.content.footer.button(of: .lineAlignment))
    #expect(mergeButton.isEnabled && mergeButton.state == .on)
    #expect(NSApp.sendAction(try #require(mergeButton.action), to: merge, from: mergeButton))
    #expect(!merge.presentation.alignsLines)
    #expect(mergeButton.state == .off)
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

      controller.toggleLineAlignment(nil)
      #expect(controller.presentation.currentBlock == block)
      let mostLines = session.rowLayout.block(atRow: Int(gridPlace))
      let leader =
        mostLines.lines(in: .b).count >= mostLines.lines(in: .a).count ? (b, Role.b) : (a, .a)
      let gridAgain = ScrollMap(session: session, from: .grid, to: .lines(leader.1))
        .sourcePosition(at: position(atReadingLineOf: leader.0))
      #expect(abs(gridAgain - gridPlace) < 0.06, "block \(block): \(gridAgain) for \(gridPlace)")

      controller.toggleLineAlignment(nil)
      #expect(abs(position(atReadingLineOf: a) - gridPlace) < 0.06, "block \(block) back")
    }
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

    for _ in 0..<2 {
      controller.toggleLineAlignment(nil)
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
    controller.toggleLineAlignment(nil)
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
    controller.toggleLineAlignment(nil)
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
    controller.toggleLineAlignment(nil)
    #expect(controller.layout.minimumWidth >= aligned + Theme.seamWidth - 1)
  }

  @Test func emptyFileShowsAHairlineWhereTheLinesOfTheOtherSideAreMissing() async throws {
    let controller = try Windows.controller(
      for: try await SampleDiffs.diff(old: "", new: "first\nsecond\n"))
    controller.toggleLineAlignment(nil)
    let (a, b) = try panes(of: controller)
    #expect(a.content.text.isEmpty)
    #expect(a.content.blocks.map(\.rows) == [0..<0])
    #expect(b.content.blocks.map(\.rows) == [0..<2])
    let band = try #require(controller.layout.seams.first?.bands.first)
    #expect(band.left.lowerBound == band.left.upperBound)
    #expect(band.right.upperBound - band.right.lowerBound > b.theme.rowHeight)
  }

  /// A window of ``SampleDiffs/everyKindOfChange(repeats:longLines:)`` with Align Lines off.
  private func connectedWindow(longLines: Bool = false) async throws -> SessionWindowController {
    let controller = try Windows.controller(
      for: try await SampleDiffs.everyKindOfChange(repeats: 16, longLines: longLines))
    controller.toggleLineAlignment(nil)
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
