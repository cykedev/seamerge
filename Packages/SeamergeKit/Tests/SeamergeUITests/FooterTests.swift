import AppKit
import MergeModel
import PaneKit
import SyntaxKit
import Testing

@testable import SeamergeUI

/// The footer: the comparison mode and the toggles of the view, each sending the command of the
/// main menu and showing the state the window is in, whichever way it changed; and Hide Footer,
/// which holds for every window and across launches.
@MainActor
@Suite struct FooterTests {
  @Test func mergeHasEveryToggleAndAComparisonHasNoBase() async throws {
    let merge = try Windows.controller(for: try await SampleMerges.helloWorld())
    #expect(
      merge.content.footer.toggles == [
        .invisibles, .lineWrapping, .collapsedLines, .scrollSynchronization, .base,
      ])
    let comparison = try Windows.controller(for: try await SampleDiffs.greeting())
    #expect(
      comparison.content.footer.toggles == [
        .invisibles, .lineWrapping, .collapsedLines, .scrollSynchronization,
      ])
    #expect(comparison.content.footer.button(of: .base) == nil)
  }

  @Test func togglesSendTheCommandsOfTheMainMenuAlongTheResponderChain() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
    let footer = controller.content.footer
    for toggle in footer.toggles {
      let button = try #require(footer.button(of: toggle))
      #expect(button.target == nil)
      #expect(button.action == toggle.command(in: button.state).action, "\(toggle)")
      let responders = sequence(first: button as NSResponder, next: \.nextResponder)
      #expect(responders.contains { $0 === controller }, "\(toggle) reaches the window")
    }
    let modes = footer.comparisonModeButton.itemArray.map(\.action)
    #expect(modes == SessionCommand.groups(in: .compare)[0].map(\.action))
  }

  @Test func eachToggleFollowsItsCommandFromTheFooterAndFromTheMenu() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
    let footer = controller.content.footer
    let cases: [(FooterToggle, initial: NSControl.StateValue, isOn: () -> Bool)] = [
      (.invisibles, .off, { controller.isSwitchedOn(.toggleInvisibles) }),
      (.lineWrapping, .off, { controller.isSwitchedOn(.toggleLineWrapping) }),
      (.scrollSynchronization, .on, { controller.isSwitchedOn(.toggleScrollSynchronization) }),
      (.base, .on, { controller.layout.showsBase }),
    ]
    for (toggle, initial, isOn) in cases {
      let button = try #require(footer.button(of: toggle))
      #expect(button.state == initial, "\(toggle) as loaded")

      // A click from the footer: the button sends its action to the first responder.
      #expect(NSApp.sendAction(try #require(button.action), to: controller, from: button))
      #expect(isOn() == (initial == .off), "\(toggle) after a click")
      #expect(button.state == (initial == .off ? .on : .off), "\(toggle) after a click")

      // The same command from the main menu or its key.
      let command = toggle.command(in: button.state)
      let item = NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
      #expect(controller.validateUserInterfaceItem(item))
      #expect(NSApp.sendAction(command.action, to: controller, from: item))
      #expect(button.state == initial, "\(toggle) after the menu")
      #expect(isOn() == (initial == .on), "\(toggle) after the menu")
    }
  }

  @Test func collapseShowsEachOfItsThreeStatesAndAClickInTheMixedStateCollapsesAll()
    async throws
  {
    let session = try await SampleMerges.manyBlocks(lineCount: 600, spacing: 30)
    let controller = try Windows.controller(for: session)
    let button = try #require(controller.content.footer.button(of: .collapsedLines))
    let pane = controller.layout.sourcePanes[0].pane
    let runs = pane.collapsedRuns
    try #require(runs.count > 1)
    #expect(button.state == .on)
    #expect(button.isEnabled)
    #expect(button.action == SessionCommand.showAllLines.action)

    // One run expanded from the pane, as a click on its bar does.
    controller.presentation.pane(pane, didAskToExpand: runs[0])
    #expect(button.state == .mixed)
    #expect(button.action == SessionCommand.collapseUnchangedLines.action)
    #expect(button.accessibilityValueDescription() == "Some lines shown")
    #expect(NSApp.sendAction(try #require(button.action), to: controller, from: button))
    #expect(pane.collapsedRuns == runs)
    #expect(button.state == .on)
    #expect(button.accessibilityValueDescription() == "Collapsed")

    // Show All Lines from the main menu.
    controller.showAllLines(nil)
    #expect(button.state == .off)
    #expect(button.toolTip == "Hide long runs of unchanged lines behind a bar")
    #expect(button.accessibilityValueDescription() == "Every line shown")
    #expect(NSApp.sendAction(try #require(button.action), to: controller, from: button))
    #expect(pane.collapsedRuns == runs)
    #expect(button.toolTip == "Show every line")
  }

  @Test func togglesThatCannotActAreDisabled() async throws {
    let short = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let footer = short.content.footer
    let collapse = try #require(footer.button(of: .collapsedLines))
    #expect(!collapse.isEnabled)
    #expect(collapse.contentTintColor == .disabledControlTextColor)
    #expect(collapse.toolTip == "Collapse unchanged lines (none in this file)")
    short.toggleResultMaximized(nil)
    let base = try #require(footer.button(of: .base))
    #expect(!base.isEnabled)
    #expect(base.toolTip == "Show or hide the base (restore the layout first)")
    let invisibles = try #require(footer.button(of: .invisibles))
    #expect(invisibles.isEnabled)
    #expect(invisibles.contentTintColor == .secondaryLabelColor)
  }

  @Test func comparisonModeShowsTheModeInUseAndRestsWhileComparing() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
    let popUp = controller.content.footer.comparisonModeButton
    #expect(popUp.titleOfSelectedItem == ComparisonMode.windowDefault.footerTitle)
    #expect(popUp.isEnabled)

    await controller.switchComparison(to: ComparisonOptions(mode: .exact))
    #expect(popUp.titleOfSelectedItem == "Exact")

    await controller.comparisonSwitcher.whileComparingAnew {
      controller.stateDidChange()
      #expect(!popUp.isEnabled)
    }
    #expect(popUp.isEnabled)
  }

  @Test func togglesSayWhatAClickDoesAndVoiceOverHearsTheirNameAndState() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
    let footer = controller.content.footer
    let invisibles = try #require(footer.button(of: .invisibles))
    #expect(invisibles.toolTip == "Show spaces, tabs and line endings")
    #expect(invisibles.accessibilityLabel() == "Invisibles")
    #expect(invisibles.accessibilityValueDescription() == "Off")
    let sync = try #require(footer.button(of: .scrollSynchronization))
    #expect(sync.accessibilityLabel() == "Synchronize Scrolling")
    #expect(sync.accessibilityValueDescription() == "On")
    #expect(footer.comparisonModeButton.accessibilityLabel() == "Comparison")
    for toggle in FooterToggle.allCases {
      // What the toggle does, then why it cannot now, in parentheses.
      for showsSingleColumn in [false, true] {
        let help = toggle.disabledHelp(showsSingleColumn: showsSingleColumn)
        #expect(help.count <= 75, "\(toggle)")
        #expect(help.hasSuffix(")") && help.contains(" ("))
      }
      for state in [NSControl.StateValue.off, .on] {
        let help = toggle.help(in: state)
        #expect(help.count <= 75, "\(toggle)")
        #expect(!help.contains(toggle.accessibilityLabel), "\(toggle): \(help)")
      }
    }
  }

  @Test func hideFooterHidesItInEveryWindowAndTheChoiceOutlastsALaunch() async throws {
    let name = "SeamergeUITests.\(UUID().uuidString)"
    let defaults = UserDefaults.privateSuite(named: name)
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = UserSettings(defaults: defaults)
    let first = try Windows.controller(for: try await SampleMerges.helloWorld(), settings: settings)
    let second = try Windows.controller(for: try await SampleDiffs.greeting(), settings: settings)
    let item = NSMenuItem(
      title: SessionCommand.toggleFooter.title, action: SessionCommand.toggleFooter.action,
      keyEquivalent: "")
    #expect(first.validateUserInterfaceItem(item))
    #expect(item.title == "Hide Footer")
    let paneBottom = { (controller: SessionWindowController) in
      controller.layout.view.frame.minY
    }
    #expect(paneBottom(first) == WindowMetrics.footerHeight)

    first.toggleFooter(nil)

    for controller in [first, second] {
      controller.content.view.layoutSubtreeIfNeeded()
      #expect(!controller.content.showsFooter)
      #expect(controller.window?.contentBorderThickness(for: .minY) == 0)
      #expect(paneBottom(controller) == 0)
    }
    #expect(second.validateUserInterfaceItem(item))
    #expect(item.title == "Show Footer")

    let relaunched = try Windows.controller(
      for: try await SampleMerges.helloWorld(), settings: UserSettings(defaults: defaults))
    #expect(!relaunched.content.showsFooter)

    second.toggleFooter(nil)
    for controller in [first, second] {
      #expect(controller.content.showsFooter)
      #expect(controller.window?.contentBorderThickness(for: .minY) == WindowMetrics.footerHeight)
    }
  }

  @Test func footerIsShownUntilTheUserHidesIt() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
    #expect(controller.content.showsFooter)
    #expect(controller.window?.contentBorderThickness(for: .minY) == WindowMetrics.footerHeight)
  }

  @Test func smallestWindowCutsNothingOff() async throws {
    for session in [try await SampleMerges.helloWorld(), try await SampleDiffs.greeting()] {
      let controller = SessionWindowController(
        session: session, context: SessionContext(), undoManager: UndoManager(),
        displayOptions: DisplayOptions(), pasteboard: .withUniqueName(),
        workspace: WorkspaceRecorder(), prompts: PromptRecorder(), doneStyle: .standard,
        settings: .private(), window: SessionWindow())
      let window = try #require(controller.window)
      defer { window.close() }
      Rendering.prepare(window, size: window.contentMinSize, appearance: Look.light.appearance)
      let footer = controller.content.footer
      footer.layoutSubtreeIfNeeded()
      let popUp = footer.comparisonModeButton
      #expect(popUp.frame.width >= popUp.intrinsicContentSize.width, "\(session.kind)")
      var right = popUp.frame.maxX
      for toggle in footer.toggles {
        let button = try #require(footer.button(of: toggle))
        #expect(button.frame.minX >= right, "\(toggle) overlaps")
        let needed = (button.image?.size.width ?? 0) + 2 * WindowMetrics.footerSymbolPadding
        #expect(button.frame.width >= needed, "\(toggle)")
        #expect(button.frame.maxX <= footer.bounds.maxX - WindowMetrics.footerInset)
        right = button.frame.maxX
      }
    }
  }

  @Test func narrowFooterShortensTheModeAndKeepsTheSymbols() throws {
    let footer = SessionFooterView(toggles: FooterToggle.allCases)
    let popUp = footer.comparisonModeButton
    footer.frame.size = CGSize(width: footer.minimumWidth, height: WindowMetrics.footerHeight)
    footer.layoutSubtreeIfNeeded()
    #expect(popUp.frame.width >= popUp.intrinsicContentSize.width)
    footer.frame.size.width = footer.minimumWidth - 40
    footer.layoutSubtreeIfNeeded()
    #expect(popUp.frame.width < popUp.intrinsicContentSize.width)
    for toggle in footer.toggles {
      let button = try #require(footer.button(of: toggle))
      #expect(button.frame.width >= WindowMetrics.footerSymbolButtonWidth, "\(toggle)")
      #expect(button.frame.maxX <= footer.bounds.maxX - WindowMetrics.footerInset, "\(toggle)")
    }
  }

  @Test func togglesShareTheHeightAndTheMiddleOfTheModeOnWholePixels() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
    let footer = controller.content.footer
    footer.layoutSubtreeIfNeeded()
    let popUp = footer.comparisonModeButton.frame
    var previous: CGRect?
    for toggle in footer.toggles {
      let frame = try #require(footer.button(of: toggle)).frame
      #expect(frame.height == popUp.height, "\(toggle)")
      #expect(frame.midY == popUp.midY, "\(toggle)")
      #expect(frame.minX == frame.minX.rounded() && frame.width == frame.width.rounded())
      if let previous {
        #expect(frame.minX - previous.maxX == WindowMetrics.footerToggleSpacing)
        #expect(frame.width == previous.width)
      }
      previous = frame
    }
    #expect(popUp.minX == WindowMetrics.footerInset)
  }

  @Test(arguments: [Look.light, .dark])
  func symbolsOfTheTogglesKeepTheirContrastOnTheFooter(look: Look) async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
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
    let resolve = { (color: NSColor) in Contrast.resolve(color, in: look.appearance) }
    let area = Contrast.over(resolve(FooterToggleButton.onFill), ground)
    let pairs: [(String, NSColor, NSColor)] = [
      ("on", Contrast.over(resolve(SessionFooterView.symbolColor(in: .on)), area), area),
      ("off", Contrast.over(resolve(SessionFooterView.symbolColor(in: .off)), ground), ground),
      ("mixed", Contrast.over(resolve(SessionFooterView.symbolColor(in: .mixed)), ground), ground),
    ]
    var lines: [String] = []
    for (state, symbol, surface) in pairs {
      let ratio = Contrast.ratio(symbol, surface)
      #expect(ratio >= 3, "\(state): \(ratio)")
      lines.append("\(state) \(String(format: "%.2f", ratio))")
    }
    // A toggle that cannot act is dimmed, visibly lighter than one that is off.
    let off = Contrast.over(resolve(SessionFooterView.symbolColor(in: .off)), ground)
    let dimmed = Contrast.over(resolve(.disabledControlTextColor), ground)
    let dimmedRatio = Contrast.ratio(dimmed, ground)
    #expect(dimmedRatio < Contrast.ratio(off, ground) - 1, "dimmed: \(dimmedRatio)")
    lines.append("dimmed \(String(format: "%.2f", dimmedRatio))")
    let outline = Contrast.over(resolve(Theme().toggleOutlineColor), ground)
    lines.append("outline of mixed \(String(format: "%.2f", Contrast.ratio(outline, ground)))")
    try Rendering.write(
      text: "\(look.name): " + lines.joined(separator: ", "), named: "footer-contrast-\(look.name)")
  }

  @Test func toolbarHasNoOptionsAnyMore() async throws {
    for session in [try await SampleMerges.helloWorld(), try await SampleDiffs.greeting()] {
      let controller = try Windows.controller(for: session)
      let toolbar = controller.toolbar
      let identifiers =
        toolbar.toolbarDefaultItemIdentifiers(toolbar.toolbar)
        + toolbar.toolbarAllowedItemIdentifiers(toolbar.toolbar)
      #expect(!identifiers.map(\.rawValue).contains("options"))
    }
  }

  @Test func languageButtonHasRoomForTheLongestNameMeasuringOnlyTheWidest() async throws {
    let footer = SessionFooterView(toggles: FooterToggle.allCases)
    let button = footer.syntaxChoiceButton
    let cell = try #require(button.cell as? NSPopUpButtonCell)
    let titleItem = try #require(cell.menuItem)
    let titles = SyntaxChoice.groups.joined().map {
      $0.languageTitle(of: $0.language(detected: .plainText))
    }
    // Every name, as the button measured them before it measured only the widest.
    let widest = titles.map { title in
      titleItem.title = title
      return cell.cellSize.width.rounded(.up)
    }.max()
    titleItem.title = ""
    #expect(footer.syntaxButtonWidth == widest)
    let measured = SessionFooterView.widestTitles(of: titles, in: button.font)
    #expect(!measured.isEmpty && measured.count < 4, "measured: \(measured)")
  }
}

extension ComparisonMode {
  /// The title of the mode in the pop-up button of the footer.
  fileprivate var footerTitle: String? {
    SessionCommand.allCases.first { $0.comparisonMode == self }?.title
  }
}
