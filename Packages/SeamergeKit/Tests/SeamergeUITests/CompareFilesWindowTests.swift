import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// The window Compare Files: how files take their places, what the default button opens, and
/// how the fields work from the keyboard and with VoiceOver.
@MainActor
@Suite(.serialized) struct CompareFilesWindowTests {
  @Test func windowIsTitledAfterWhatItDoesAndKeepsItsSize() throws {
    let fixture = try CompareFilesFixture()
    #expect(fixture.window.title == "Compare Files")
    #expect(!fixture.window.styleMask.contains(.resizable))
    #expect(fixture.window.collectionBehavior.contains(.fullScreenNone))
    #expect(fixture.window.toolbar == nil)
  }

  @Test func twoDroppedFilesFillTheOuterFields() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let (old, new) = (try files.file("old.txt"), try files.file("new.txt"))

    #expect(fixture.controller.acceptDrop(DragInTest(files: [old, new]), onto: nil))

    #expect(fixture.controller.selection[.left] == old)
    #expect(fixture.controller.selection[.base] == nil)
    #expect(fixture.controller.selection[.right] == new)
    #expect(fixture.captions == ["Left", "Base (Optional)", "Right"])
  }

  @Test(arguments: [nil, FileSlot.right])
  func threeDroppedFilesFillEveryFieldInOrder(droppedOn slot: FileSlot?) throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let urls = [try files.file("a.txt"), try files.file("base.txt"), try files.file("b.txt")]

    #expect(fixture.controller.acceptDrop(DragInTest(files: urls), onto: slot))

    #expect(FileSlot.allCases.map { fixture.controller.selection[$0] } == urls)
    #expect(fixture.captions == ["A", "Base", "B"])
  }

  @Test func oneFileTakesTheFieldItIsDroppedOnOrElseTheFirstFreeOne() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let (first, second, third) = (
      try files.file("1.txt"), try files.file("2.txt"), try files.file("3.txt")
    )

    #expect(fixture.controller.acceptDrop(DragInTest(files: [first]), onto: .base))
    #expect(fixture.controller.acceptDrop(DragInTest(files: [second]), onto: nil))
    #expect(fixture.controller.acceptDrop(DragInTest(files: [third]), onto: nil))

    #expect(fixture.controller.selection[.base] == first)
    #expect(fixture.controller.selection[.left] == second)
    #expect(fixture.controller.selection[.right] == third)
    #expect(fixture.controller.operation(forDrag: DragInTest(files: [first]), onto: nil) == [])
  }

  @Test func foldersAndMoreThanThreeFilesAreRefused() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let four = try (1...4).map { try files.file("\($0).txt") }
    let folder = try files.subfolder("folder")

    for urls in [four, [folder], [four[0], folder]] {
      let drag = DragInTest(files: urls)
      #expect(fixture.controller.operation(forDrag: drag, onto: .left) == [])
      #expect(!fixture.controller.acceptDrop(drag, onto: .left))
    }
    #expect(!fixture.controller.fill(with: four))
    #expect(fixture.controller.selection.isEmpty)
  }

  @Test func filesFromTheDockLandInTheFieldsLikeADrop() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let urls = [try files.file("a.txt"), try files.file("b.txt")]

    #expect(fixture.controller.fill(with: urls))

    #expect(
      fixture.controller.selection.comparison == FileComparison(left: urls[0], right: urls[1]))
  }

  @Test func dropShowsTheFieldsItWouldFill() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let drag = DragInTest(files: [try files.file("a.txt"), try files.file("b.txt")])

    #expect(fixture.controller.operation(forDrag: drag, onto: nil) == .copy)
    #expect(try fixture.field(.left).isDropTarget)
    #expect(try !fixture.field(.base).isDropTarget)
    #expect(try fixture.field(.right).isDropTarget)

    fixture.controller.dragDidEnd()
    #expect(try FileSlot.allCases.allSatisfy { try !fixture.field($0).isDropTarget })
  }

  @Test func swapSidesSwapsTheOuterFieldsOnceOneIsFilled() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let item = NSMenuItem(
      title: "Swap Sides", action: #selector(CompareFilesWindowController.swapSides(_:)),
      keyEquivalent: "")
    #expect(!fixture.controller.validateUserInterfaceItem(item))

    let (old, base) = (try files.file("old.txt"), try files.file("base.txt"))
    #expect(fixture.controller.acceptDrop(DragInTest(files: [old]), onto: .left))
    #expect(fixture.controller.acceptDrop(DragInTest(files: [base]), onto: .base))
    #expect(fixture.controller.validateUserInterfaceItem(item))

    fixture.controller.swapSides(nil)

    #expect(fixture.controller.selection[.left] == nil)
    #expect(fixture.controller.selection[.base] == base)
    #expect(fixture.controller.selection[.right] == old)
    #expect(fixture.announcements.last == "Swapped A and B")
  }

  @Test func fieldDraggedOntoAnotherSwapsTheTwo() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let (old, new) = (try files.file("old.txt"), try files.file("new.txt"))
    #expect(fixture.controller.fill(with: [old, new]))
    let drag = DragInTest(field: try fixture.field(.right))

    #expect(fixture.controller.operation(forDrag: drag, onto: .right) == [])
    #expect(fixture.controller.operation(forDrag: drag, onto: .base) == .move)
    #expect(fixture.controller.acceptDrop(drag, onto: .left))

    #expect(fixture.controller.selection[.left] == new)
    #expect(fixture.controller.selection[.right] == old)
    #expect(fixture.announcements.last == "Swapped Right and Left")
  }

  @Test func defaultButtonOpensOnlyTwoOuterOrThreeFiles() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let (a, base, b) = (
      try files.file("a.txt"), try files.file("base.txt"), try files.file("b.txt")
    )
    let button = fixture.controller.openButton
    #expect(button.keyEquivalent == "\r")

    let states: [(drops: [(URL, FileSlot)], title: String, isEnabled: Bool)] = [
      ([], "Compare", false),
      ([(a, .left)], "Compare", false),
      ([(base, .base)], "Merge", false),
      ([(b, .right)], "Merge", true),
    ]
    var expected: [(String, Bool)] = []
    var seen: [(String, Bool)] = []
    for state in states {
      for (url, slot) in state.drops {
        #expect(fixture.controller.acceptDrop(DragInTest(files: [url]), onto: slot))
      }
      expected.append((state.title, state.isEnabled))
      seen.append((button.title, button.isEnabled))
    }
    #expect(seen.map(\.0) == expected.map(\.0))
    #expect(seen.map(\.1) == expected.map(\.1))

    fixture.controller.fileFieldDidAskToClear(try fixture.field(.base))
    #expect(button.title == "Compare")
    #expect(button.isEnabled)
  }

  @Test func comparisonThatTheAppCannotOpenLeavesTheButtonDeactivated() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    fixture.delegate.openableKinds = [.merge]
    #expect(fixture.controller.fill(with: [try files.file("a.txt"), try files.file("b.txt")]))

    #expect(fixture.controller.openButton.title == "Compare")
    #expect(!fixture.controller.openButton.isEnabled)
    fixture.controller.openComparison(nil)
    #expect(fixture.delegate.opened.isEmpty)
  }

  @Test(arguments: [2, 3])
  func defaultButtonOpensExactlyTheShownRoles(fileCount: Int) async throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let urls = try (1...fileCount).map { try files.file("\($0).txt") }
    #expect(fixture.controller.fill(with: urls))
    fixture.controller.swapSides(nil)
    let closes = NotificationCenter.default.notifications(named: NSWindow.willCloseNotification)

    fixture.controller.openButton.performClick(nil)
    #expect(!fixture.controller.openButton.isEnabled)
    await fixture.delegate.nextOpening()

    let opened = try #require(fixture.delegate.opened.first)
    #expect(opened.left == urls[urls.count - 1])
    #expect(opened.base == (fileCount == 3 ? urls[1] : nil))
    #expect(opened.right == urls[0])
    #expect(opened.kind == (fileCount == 3 ? .merge : .diff))
    for await notification in closes where notification.object as? NSWindow === fixture.window {
      break
    }
    #expect(fixture.controller.selection.isEmpty)
    #expect(fixture.recentComparisons.comparisons == [opened])
  }

  @Test func filesThatCannotBeOpenedStayWithTheirReasonAndAreNotRemembered() async throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let urls = [try files.file("a.txt"), try files.file("o.txt"), try files.file("b.png")]
    fixture.delegate.failure = SessionLoadingError.binaryFile(urls[2])
    #expect(fixture.controller.fill(with: urls))

    fixture.controller.openButton.performClick(nil)
    await fixture.delegate.nextOpening()

    #expect(fixture.panels.failures == ["“b.png” isn’t a text file."])
    #expect(FileSlot.allCases.map { fixture.controller.selection[$0] } == urls)
    #expect(fixture.controller.openButton.isEnabled)
    #expect(fixture.recentComparisons.comparisons.isEmpty)
  }

  @Test func everyFieldIsFilledAndClearedFromTheKeyboard() async throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    for slot in FileSlot.allCases {
      let url = try files.file("\(slot).txt")
      fixture.panels.files = [url]
      let field = try fixture.field(slot)

      try fixture.type(" ", into: field)
      await fixture.panels.nextChoice()
      #expect(fixture.controller.selection[slot] == url)
      #expect(fixture.window.firstResponder === field)

      try fixture.type("\u{7F}", into: field)
      #expect(fixture.controller.selection[slot] == nil)
    }
    #expect(fixture.panels.roles == ["Left", "Base (Optional)", "Right"])
  }

  @Test func tabRunsThroughTheFieldsFromLeftToRight() throws {
    let fixture = try CompareFilesFixture()
    fixture.window.makeFirstResponder(try fixture.field(.left))

    var order: [NSResponder?] = [fixture.window.firstResponder]
    for _ in 1...2 {
      fixture.window.selectNextKeyView(nil)
      order.append(fixture.window.firstResponder)
    }

    #expect(order == (try FileSlot.allCases.map { try fixture.field($0) }))
  }

  @Test func windowOpensWithTheFocusOnTheFirstEmptyField() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    #expect(
      fixture.controller.acceptDrop(DragInTest(files: [try files.file("a.txt")]), onto: .left))

    fixture.controller.showWindow(nil)

    #expect(fixture.window.firstResponder === (try fixture.field(.base)))
    fixture.window.close()
  }

  @Test func everyFieldTellsVoiceOverItsRoleAndContent() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let left = try files.file("LoginView.swift")
    let folder = FileField.folderName(of: left)

    var labels = try FileSlot.allCases.map { try fixture.field($0).accessibilityLabel() ?? "" }
    var values = try FileSlot.allCases.map {
      try fixture.field($0).accessibilityValue() as? String ?? ""
    }
    #expect(labels == ["Left", "Base, optional", "Right"])
    #expect(values == ["empty", "empty", "empty"])
    #expect(try fixture.field(.left).accessibilityRole() == .button)

    #expect(fixture.controller.acceptDrop(DragInTest(files: [left]), onto: .left))
    #expect(fixture.controller.acceptDrop(DragInTest(files: [left]), onto: .base))
    labels = try FileSlot.allCases.map { try fixture.field($0).accessibilityLabel() ?? "" }
    values = try FileSlot.allCases.map {
      try fixture.field($0).accessibilityValue() as? String ?? ""
    }
    #expect(labels == ["A", "Base", "B"])
    #expect(values[0] == "LoginView.swift, in \(folder)")
    #expect(values[2] == "empty")
    #expect(
      fixture.announcements == ["LoginView.swift added as Left", "LoginView.swift added as Base"])
  }

  @Test func emptyingAFieldIsAnnouncedAndWorksForVoiceOver() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    #expect(
      fixture.controller.acceptDrop(DragInTest(files: [try files.file("a.txt")]), onto: .right))
    let field = try fixture.field(.right)
    let remove = try #require(field.accessibilityCustomActions()?.first)
    #expect(remove.name == "Remove File")

    #expect(remove.handler?() == true)

    #expect(fixture.controller.selection[.right] == nil)
    #expect(fixture.announcements.last == "a.txt removed from Right")
    #expect(field.accessibilityCustomActions() == nil)
  }

  @Test func filledFieldShowsTheFullPathAsItsHelpTag() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let url = try files.file("a.txt")
    #expect(fixture.controller.fill(with: [url]))

    #expect(try fixture.field(.left).toolTip == url.path(percentEncoded: false))
    #expect(try fixture.field(.right).toolTip == nil)
  }
}
