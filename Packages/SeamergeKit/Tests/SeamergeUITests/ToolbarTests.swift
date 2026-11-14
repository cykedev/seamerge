import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The toolbar: the number of open conflicts with arrows that follow the jumps, and Done, which acts only with a responder that saves and stands out once no
/// conflict is open.
@MainActor
@Suite struct ToolbarTests {
  @Test func toolbarHasTheConflictsAndDoneAndMoreToDragIn() throws {
    let toolbar = SessionToolbar(kind: .merge, doneStyle: .standard)
    let defaults = toolbar.toolbarDefaultItemIdentifiers(toolbar.toolbar)
    #expect(defaults == [.conflictCount, .conflictNavigation, .flexibleSpace, .done])
    #expect(toolbar.toolbar.centeredItemIdentifiers == [.conflictCount, .conflictNavigation])
    let allowed = toolbar.toolbarAllowedItemIdentifiers(toolbar.toolbar)
    #expect(allowed.contains(.changeNavigation))
    #expect(allowed.contains(.comparison))
    #expect(!defaults.contains(.changeNavigation))
    #expect(toolbar.toolbar.allowsUserCustomization)
  }

  @Test func countSaysHowManyConflictsAreLeft() {
    #expect(
      SessionToolbar.countText(openConflictCount: 2, hasConflicts: true) == "2 Conflicts Left")
    #expect(SessionToolbar.countText(openConflictCount: 1, hasConflicts: true) == "1 Conflict Left")
    #expect(
      SessionToolbar.countText(openConflictCount: 0, hasConflicts: true) == "All Conflicts Resolved"
    )
    #expect(SessionToolbar.countText(openConflictCount: 0, hasConflicts: false) == "No Conflicts")
  }

  @Test func arrowsFollowTheConflictJumpsAndGoOnceAllAreResolved() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let items = try toolbarItems(of: controller)
    let navigation = try #require(items[.conflictNavigation] as? NSToolbarItemGroup)
    let (previous, next) = (navigation.subitems[0], navigation.subitems[1])
    #expect(previous.action == SessionCommand.previousConflict.action)
    #expect(next.action == SessionCommand.nextConflict.action)
    #expect(!previous.isEnabled)
    #expect(next.isEnabled)
    #expect(previous.toolTip == "Go back to the open conflict before this one")
    #expect(next.toolTip == SessionCommand.nextConflict.help)
    #expect(previous.image?.accessibilityDescription == "Previous Conflict")
    controller.selectLastChange(nil)
    #expect(previous.isEnabled)
    #expect(!next.isEnabled)
    #expect(!navigation.isHidden)
    #expect(countLabel(of: controller)?.hasSuffix("Conflicts Left") == true)

    controller.resolveOpenConflicts(with: [.b])
    #expect(navigation.isHidden)
    #expect(countLabel(of: controller) == "All Conflicts Resolved")
  }

  @Test func doneSavesAndClosesAndStandsOutWhenNoConflictIsOpen() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
    let done = try #require(try toolbarItems(of: controller)[.done])
    #expect(done.action == SessionCommand.saveAndClose.action)
    #expect(done.toolTip == "Save and close")
    #expect(done.title == "Done")
    #expect(done.isEnabled)
    #expect(done.style == .plain)

    controller.resolveOpenConflicts(with: [.a])
    #expect(done.style == .prominent)
  }

  @Test func checkmarkStandsAtTheEnd() throws {
    let toolbar = SessionToolbar(kind: .merge, doneStyle: .checkmark)
    let defaults = toolbar.toolbarDefaultItemIdentifiers(toolbar.toolbar)
    #expect(defaults.suffix(2) == [.flexibleSpace, .done])
    let done = try #require(
      toolbar.toolbar(
        toolbar.toolbar, itemForItemIdentifier: .done, willBeInsertedIntoToolbar: false))
    #expect(done.image != nil)
    #expect(done.label == "Done")
  }

  @Test func comparisonModeCanBeDraggedInWithTheCommandsOfTheCompareMenu() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
    let comparison = try #require(
      controller.toolbar.toolbar(
        controller.toolbar.toolbar, itemForItemIdentifier: .comparison,
        willBeInsertedIntoToolbar: false))
    #expect(comparison.image?.accessibilityDescription == "Comparison")
    let menu = try #require((comparison as? NSMenuToolbarItem)?.menu)
    let actions = menu.items.filter { !$0.isSeparatorItem }.compactMap(\.action)
    #expect(actions == SessionCommand.groups(in: .compare).joined().map(\.action))
  }

  @Test func countShowsThatAComparisonIsUnderWay() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
    controller.showsComparisonProgress = true
    controller.stateDidChange()
    #expect(countLabel(of: controller) == "Comparing…")
  }

  @Test func subtitleEndsBeforeTheNumberOfConflicts() async throws {
    let scenario = try #require(Scenario.merges.first { $0.name == "rebase" })
    let (session, context) = try await scenario.load()
    let controller = try Windows.controller(for: session, context: context)
    let window = try #require(controller.window)
    let summary = SessionSummary(
      changes: controller.presentation.changes, context: context,
      arrangement: controller.presentation.arrangement, startMode: .windowDefault)
    window.setContentSize(CGSize(width: 1280, height: 800))
    #expect(window.subtitle == summary.fullSubtitle)
    window.setContentSize(CGSize(width: 900, height: 800))
    window.contentView?.superview?.layoutSubtreeIfNeeded()
    controller.windowDidResize(Notification(name: NSWindow.didResizeNotification))
    #expect(window.subtitle != summary.fullSubtitle)
    let font = NSFont.preferredFont(forTextStyle: .subheadline)
    let width = (window.subtitle as NSString).size(withAttributes: [.font: font]).width
    let end = try #require(controller.toolbar.countMinX)
    #expect(WindowMetrics.titlebarControlsWidth + width <= end)
  }

  @Test(arguments: [Session.Kind.diff, .merge])
  func everyItemOfTheToolbarStaysInViewInTheSmallestWindow(kind: Session.Kind) async throws {
    let session =
      switch kind {
      case .diff: try await SampleDiffs.greeting()
      case .merge: try await SampleMerges.merge(base: nil, a: "a\n", b: "b\n")
      }
    let controller = try Windows.controller(for: session, context: SampleDiffs.gitContext)
    let window = try #require(controller.window)
    Rendering.prepare(window, size: window.contentMinSize, appearance: Look.light.appearance)
    window.contentView?.superview?.layoutSubtreeIfNeeded()

    let toolbar = controller.toolbar.toolbar
    let visible = Set((toolbar.visibleItems ?? []).map(\.itemIdentifier))
    let shown = toolbar.items.filter { !$0.isHidden }.map(\.itemIdentifier)
    #expect(Set(shown).isSubset(of: visible), "\(kind): \(visible)")
    #expect(window.contentMinSize.width >= WindowMetrics.minimumToolbarWidth)
  }

  /// The items of the toolbar of the window, by their identifiers.
  private func toolbarItems(
    of controller: SessionWindowController
  ) throws -> [NSToolbarItem.Identifier: NSToolbarItem] {
    let toolbar = try #require(controller.window?.toolbar)
    return Dictionary(toolbar.items.map { ($0.itemIdentifier, $0) }) { first, _ in first }
  }

  private func countLabel(of controller: SessionWindowController) -> String? {
    controller.toolbar.toolbar.items.first { $0.itemIdentifier == .conflictCount }?.view?
      .accessibilityLabel()
  }
}
