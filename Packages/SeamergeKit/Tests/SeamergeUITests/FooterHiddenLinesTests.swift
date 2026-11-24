import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The number of collapsed lines in the footer: the sum of the numbers on the bars of unchanged
/// lines, following each run that expands or collapses, nothing while none is collapsed, not the
/// lines a patch passes over, and the first part of the footer to go when the window narrows.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct FooterHiddenLinesTests {
  @Test func footerSumsTheNumbersOnTheBarsWhileEverythingIsCollapsed() async throws {
    // Twelve changed lines: eleven runs of 19 unchanged lines between them, each collapsed but
    // for three lines on either side, and 17 lines after the last, collapsed to the end.
    let controller = try Windows.controller(for: try await SampleDiffs.manyChanges())
    let footer = controller.content.footer
    footer.layoutSubtreeIfNeeded()
    let bars = controller.layout.sourcePanes.map { $0.pane.collapsedRuns.map(\.rows.count) }
    #expect(bars.allSatisfy { $0.reduce(0, +) == 11 * 13 + 14 }, "\(bars)")
    #expect(footer.hiddenLinesField.stringValue == "157 Lines Hidden")
    #expect(!footer.hiddenLinesField.isHidden)
    #expect(footer.accessibilityValue() as? String == "157 lines hidden")
  }

  @Test func numberFollowsARunThatExpandsAndShowAllLinesAndCollapsingAgain() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.manyChanges())
    let footer = controller.content.footer
    let label = footer.hiddenLinesField
    let pane = controller.layout.sourcePanes[0].pane
    let run = try #require(pane.collapsedRuns.first)
    #expect(run.rows.count == 13)

    controller.presentation.pane(pane, didAskToExpand: run)
    #expect(label.stringValue == "144 Lines Hidden")
    #expect(footer.accessibilityValue() as? String == "144 lines hidden")

    controller.presentation.pane(pane, didAskToCollapse: run)
    #expect(label.stringValue == "157 Lines Hidden")

    controller.showAllLines(nil)
    footer.layoutSubtreeIfNeeded()
    #expect(label.isHidden)
    #expect(footer.accessibilityValue() == nil)

    controller.collapseUnchangedLines(nil)
    footer.layoutSubtreeIfNeeded()
    #expect(label.stringValue == "157 Lines Hidden")
    #expect(!label.isHidden)
  }

  @Test func mergeCountsEachRunOnceThoughEveryPaneShowsItsBar() async throws {
    let controller = try Windows.controller(
      for: try await SampleMerges.manyBlocks(lineCount: 600, spacing: 30))
    let runs = controller.layout.sourcePanes[0].pane.collapsedRuns
    try #require(runs.count > 1)
    let sum = runs.map(\.rows.count).reduce(0, +)
    #expect(controller.layout.resultPane?.collapsedRuns.map(\.rows.count).reduce(0, +) == sum)
    #expect(controller.content.footer.hiddenLinesField.stringValue == "\(sum) Lines Hidden")
  }

  @Test func fileWithoutLongRunsOfUnchangedLinesShowsNoNumber() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())
    let footer = controller.content.footer
    footer.layoutSubtreeIfNeeded()
    #expect(controller.layout.sourcePanes[0].pane.collapsedRuns.isEmpty)
    #expect(footer.hiddenLinesField.isHidden)
    #expect(footer.accessibilityValue() == nil)
    #expect(footer.accessibilityLabel() == "Footer")
  }

  @Test func linesThatAPatchPassesOverAreNotHidden() async throws {
    let files = try SampleFiles()
    let cache = PatchCache(
      folder: files.folder.appending(path: "Patch", directoryHint: .isDirectory))
    let copy = try await cache.keep(Data(Self.patchWithALongHunk.utf8), fileName: "long.patch")
    let controller = try await SessionWindowController.openPatch(
      copy, undoManager: UndoManager(), settings: .private())
    await controller.phase.filling?.value
    defer { controller.window?.close() }
    let footer = controller.content.footer
    footer.layoutSubtreeIfNeeded()
    let pane = try #require(controller.layout.sourcePane(.b))
    #expect(pane.collapsedRuns.map(\.missingLineCount) == [4, nil, 15])
    #expect(pane.collapsedRuns.map(\.rows.count) == [1, 8, 1])
    #expect(footer.hiddenLinesField.stringValue == "8 Lines Hidden")

    // The bars of the lines not in the patch stay; Show All Lines then has nothing left to show,
    // and the toggle is off rather than mixed.
    controller.showAllLines(nil)
    footer.layoutSubtreeIfNeeded()
    #expect(pane.collapsedRuns.map(\.missingLineCount) == [4, 15])
    #expect(footer.hiddenLinesField.isHidden)
    #expect(!controller.canPerform(.showAllLines))
    #expect(footer.button(of: .collapsedLines)?.state == .off)
  }

  @Test func numberIsQuietTextWithAHelpTagThatVoiceOverHearsAsTheValueOfTheFooter() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.manyChanges())
    let label = controller.content.footer.hiddenLinesField
    #expect(label.toolTip == "Show them with View > Show All Lines")
    #expect(try #require(label.toolTip).count <= 75)
    #expect(!label.isAccessibilityElement())
    #expect(label.font == controller.content.footer.comparisonModeButton.font)
    let quietText = CompareFilesColors(controller.displayOptions).quietText
    for look in [Look.light, .dark] {
      #expect(
        Contrast.resolve(label.textColor, in: look.appearance)
          == Contrast.resolve(quietText, in: look.appearance), "\(look.name)")
    }
  }

  @Test(arguments: Look.all)
  func numberKeepsTheContrastOfTextOnTheFooter(look: Look) async throws {
    let options = DisplayOptions(increasesContrast: look.increasesContrast)
    let controller = try Windows.controller(
      for: try await SampleDiffs.manyChanges(), options: options)
    let window = try #require(controller.window)
    defer { window.close() }
    Rendering.prepare(window, size: WindowMetrics.defaultContentSize, appearance: look.appearance)
    let bitmap = try Rendering.bitmap(of: window)
    // The system draws the bottom border of the window; its color is read where it is empty.
    let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
    let sample = try #require(
      bitmap.colorAt(
        x: Int((bitmap.size.width - 40) * scale),
        y: Int((bitmap.size.height - WindowMetrics.footerHeight / 2) * scale)))
    let ground = Contrast.over(sample, .white)
    let text = try #require(
      Contrast.resolve(controller.content.footer.hiddenLinesField.textColor, in: look.appearance))
    let ratio = Contrast.ratio(Contrast.over(text, ground), ground)
    #expect(ratio >= 4.5, "\(look.name): \(ratio)")
    try Rendering.write(
      text: "\(look.name): \(String(format: "%.2f", ratio))",
      named: "footer-hidden-lines-contrast-\(look.name)")
  }

  @Test func numberStandsWholeInAWindowOfTheDefaultSize() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.manyChanges())
    let window = try #require(controller.window)
    defer { window.close() }
    Rendering.prepare(
      window, size: WindowMetrics.defaultContentSize, appearance: Look.light.appearance)
    let footer = controller.content.footer
    footer.layoutSubtreeIfNeeded()
    let label = footer.hiddenLinesField
    let needed = try #require(label.cell).cellSize
    #expect(!label.isHidden)
    #expect(
      label.frame.width >= needed.width,
      "frame \(label.frame), cell \(needed)")
  }

  @Test func oneHiddenLineIsNamedInTheSingular() throws {
    let footer = SessionFooterView(toggles: FooterToggle.allCases)
    footer.show(Self.state(hiddenLineCount: 1))
    #expect(footer.hiddenLinesField.stringValue == "1 Line Hidden")
    #expect(footer.accessibilityValue() as? String == "1 line hidden")
  }

  @Test func narrowFooterDropsTheNumberBeforeTheModeShortens() throws {
    let footer = SessionFooterView(toggles: FooterToggle.allCases)
    footer.show(Self.state(hiddenLineCount: 51))
    let label = footer.hiddenLinesField
    let popUp = footer.comparisonModeButton
    let labelWidth = try #require(label.cell).cellSize.width.rounded(.up)
    let needed = footer.minimumWidth + WindowMetrics.footerGroupSpacing + labelWidth
    footer.frame.size = CGSize(width: needed, height: WindowMetrics.footerHeight)
    footer.layoutSubtreeIfNeeded()
    #expect(!label.isHidden)
    #expect(label.frame.maxX <= footer.bounds.maxX - WindowMetrics.footerInset)
    let lastToggle = try #require(footer.button(of: .base))
    #expect(label.frame.minX - lastToggle.frame.maxX == WindowMetrics.footerGroupSpacing)
    #expect(label.frame.midY == popUp.frame.midY)

    footer.frame.size.width = needed - 1
    footer.layoutSubtreeIfNeeded()
    #expect(label.isHidden)
    #expect(popUp.frame.width >= popUp.intrinsicContentSize.width)
  }

  @Test func smallestWindowCutsNothingOff() async throws {
    for session in [
      try await SampleDiffs.manyChanges(),
      try await SampleMerges.manyBlocks(lineCount: 600, spacing: 30),
    ] {
      let controller = try Windows.controller(for: session)
      let window = try #require(controller.window)
      defer { window.close() }
      Rendering.prepare(window, size: window.contentMinSize, appearance: Look.light.appearance)
      let footer = controller.content.footer
      footer.layoutSubtreeIfNeeded()
      let label = footer.hiddenLinesField
      let popUp = footer.comparisonModeButton
      #expect(controller.presentation.hiddenLineCount > 0)
      #expect(popUp.frame.width >= popUp.intrinsicContentSize.width, "\(session.kind)")
      if !label.isHidden {
        let labelWidth = try #require(label.cell).cellSize.width
        #expect(label.frame.width >= labelWidth, "\(session.kind)")
        #expect(label.frame.maxX <= footer.bounds.maxX - WindowMetrics.footerInset)
      }
      #expect(footer.accessibilityValue() != nil, "\(session.kind)")
    }
  }

  /// A state of the footer with `hiddenLineCount` collapsed lines and every control enabled.
  private static func state(hiddenLineCount: Int) -> SessionFooterView.State {
    SessionFooterView.State(
      mode: .ignoreWhitespaceChanges, canChangeMode: true,
      toggles: Dictionary(
        uniqueKeysWithValues: FooterToggle.allCases.map {
          ($0, SessionFooterView.State.Toggle(state: .off, isEnabled: true))
        }),
      syntaxChoice: .automatic, language: "Swift", automaticTitle: "Automatic (Swift)",
      canChooseSyntax: true, showsSingleColumn: false, hiddenLineCount: hiddenLineCount)
  }

  /// A patch of a file of more than 42 lines with a hunk from line 5 to 24, whose 14 lines after
  /// the change collapse, and a hunk around line 41; the patch passes over lines 1 to 4 and 25
  /// to 39.
  static let patchWithALongHunk: String = {
    let before = (5...9).map { " line \($0)" }
    let after = (11...24).map { " line \($0)" }
    let lines =
      ["--- a/numbers.txt", "+++ b/numbers.txt", "@@ -5,20 +5,20 @@"] + before
      + ["-line 10", "+ten"] + after
      + ["@@ -40,3 +40,3 @@", " line 40", "-line 41", "+forty-one", " line 42"]
    return lines.joined(separator: "\n") + "\n"
  }()
}
