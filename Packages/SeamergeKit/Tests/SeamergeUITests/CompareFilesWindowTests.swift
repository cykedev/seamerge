import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// The sheets Compare Files, Merge Files and Change Files: how files take their places, what the
/// default button opens, and how the fields work from the keyboard and with VoiceOver.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct CompareFilesWindowTests {
  @Test func sheetHasTheFieldsAndTheTitlesOfItsPurpose() throws {
    let cases: [(CompareFilesWindowController.Purpose, String, [String], String)] = [
      (.compare, "Compare Files", ["Left", "Right"], "Compare"),
      (.merge, "Merge Files", ["A", "Base", "B"], "Merge"),
      (.change(.diff), "Change Files", ["Left", "Right"], "Change"),
      (.change(.merge), "Change Files", ["A", "Base", "B"], "Change"),
    ]
    for (purpose, title, captions, button) in cases {
      let fixture = CompareFilesFixture(purpose)
      #expect(fixture.window.title == title)
      #expect(fixture.captions == captions)
      #expect(fixture.controller.fields.count == captions.count)
      #expect(fixture.controller.openButton.title == button)
    }
  }

  @Test func twoDroppedFilesFillTheFieldsOfAComparison() throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture()
    let (old, new) = (try files.file("old.txt"), try files.file("new.txt"))

    #expect(fixture.controller.acceptDrop(DragInTest(files: [old, new]), onto: nil))

    #expect(fixture.files == [old, new])
    #expect(fixture.captions == ["Left", "Right"])
  }

  @Test(arguments: [nil, FileSlot.right])
  func threeDroppedFilesFillEveryFieldOfAMergeInOrder(droppedOn slot: FileSlot?) throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture(.merge)
    let urls = [try files.file("a.txt"), try files.file("base.txt"), try files.file("b.txt")]

    #expect(fixture.controller.acceptDrop(DragInTest(files: urls), onto: slot))

    #expect(fixture.files == urls)
    #expect(fixture.captions == ["A", "Base", "B"])
  }

  @Test func twoDroppedFilesFillTheOuterFieldsOfAMerge() throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture(.merge)
    let (a, b) = (try files.file("a.txt"), try files.file("b.txt"))

    #expect(fixture.controller.acceptDrop(DragInTest(files: [a, b]), onto: nil))

    #expect(fixture.files == [a, nil, b])
  }

  @Test func oneFileTakesTheFieldItIsDroppedOnOrElseTheFirstFreeOne() throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture(.merge)
    let (first, second, third) = (
      try files.file("1.txt"), try files.file("2.txt"), try files.file("3.txt")
    )

    #expect(fixture.controller.acceptDrop(DragInTest(files: [first]), onto: .base))
    #expect(fixture.controller.acceptDrop(DragInTest(files: [second]), onto: nil))
    #expect(fixture.controller.acceptDrop(DragInTest(files: [third]), onto: nil))

    #expect(fixture.files == [second, first, third])
    #expect(fixture.controller.operation(forDrag: DragInTest(files: [first]), onto: nil) == [])
  }

  @Test func whatTheFieldsCannotHoldIsRefused() throws {
    let files = try SampleFiles()
    let four = try (1...4).map { try files.file("\($0).txt") }
    let folder = try files.subfolder("folder")
    let cases: [(CompareFilesWindowController.Purpose, [URL], FileSlot?)] = [
      (.merge, four, .left), (.merge, [folder], .left), (.merge, [four[0], folder], nil),
      (.compare, Array(four.prefix(3)), nil), (.compare, [folder, folder, folder], nil),
      (.change(.diff), [folder], .left),
    ]

    for (purpose, urls, slot) in cases {
      let fixture = CompareFilesFixture(purpose)
      let drag = DragInTest(files: urls)
      #expect(fixture.controller.operation(forDrag: drag, onto: slot) == [], "\(purpose)")
      #expect(!fixture.controller.acceptDrop(drag, onto: slot), "\(purpose)")
      #expect(!fixture.controller.fill(with: urls), "\(purpose)")
      #expect(fixture.controller.selection.isEmpty, "\(purpose)")
    }
  }

  @Test func filesFromTheDockLandInTheFieldsLikeADrop() throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture()
    let urls = [try files.file("a.txt"), try files.file("b.txt")]

    #expect(fixture.controller.fill(with: urls))

    #expect(
      fixture.controller.selection.comparison == FileComparison(left: urls[0], right: urls[1]))
  }

  @Test func dropShowsTheFieldsItWouldFill() throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture(.merge)
    let drag = DragInTest(files: [try files.file("a.txt"), try files.file("b.txt")])

    #expect(fixture.controller.operation(forDrag: drag, onto: nil) == .copy)
    #expect(try fixture.field(.left).isDropTarget)
    #expect(try !fixture.field(.base).isDropTarget)
    #expect(try fixture.field(.right).isDropTarget)
    #expect(fixture.captions == ["Drop to Use as A", "Base", "Drop to Use as B"])

    fixture.controller.dragDidEnd()
    #expect(try FileSlot.allCases.allSatisfy { try !fixture.field($0).isDropTarget })
  }

  @Test func swapSidesSwapsTheOuterFieldsOnceOneIsFilled() throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture(.merge)
    let item = NSMenuItem(
      title: "Swap Sides", action: #selector(CompareFilesWindowController.swapSides(_:)),
      keyEquivalent: "")
    #expect(!fixture.controller.validateUserInterfaceItem(item))

    let (old, base) = (try files.file("old.txt"), try files.file("base.txt"))
    #expect(fixture.controller.acceptDrop(DragInTest(files: [old]), onto: .left))
    #expect(fixture.controller.acceptDrop(DragInTest(files: [base]), onto: .base))
    #expect(fixture.controller.validateUserInterfaceItem(item))

    fixture.controller.swapSides(nil)

    #expect(fixture.files == [nil, base, old])
    #expect(fixture.announcements.last == "Swapped A and B")
  }

  @Test func fieldDraggedOntoAnotherSwapsTheTwo() throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture()
    let (old, new) = (try files.file("old.txt"), try files.file("new.txt"))
    #expect(fixture.controller.fill(with: [old, new]))
    let drag = DragInTest(field: try fixture.field(.right))

    #expect(fixture.controller.operation(forDrag: drag, onto: .right) == [])
    #expect(fixture.controller.operation(forDrag: drag, onto: .left) == .move)
    #expect(fixture.controller.acceptDrop(drag, onto: .left))

    #expect(fixture.files == [new, old])
    #expect(fixture.announcements.last == "Swapped Right and Left")
  }

  @Test(arguments: [CompareFilesWindowController.Purpose.compare, .merge])
  func defaultButtonOpensOnceEveryFieldIsFilled(purpose: CompareFilesWindowController.Purpose)
    throws
  {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture(purpose)
    let button = fixture.controller.openButton
    #expect(button.keyEquivalent == "\r")

    var states: [Bool] = [button.isEnabled]
    for slot in fixture.controller.selection.slots {
      #expect(
        fixture.controller.acceptDrop(
          DragInTest(files: [try files.file("\(slot).txt")]), onto: slot))
      states.append(button.isEnabled)
    }
    #expect(states == Array(repeating: false, count: states.count - 1) + [true])

    fixture.controller.fileFieldDidAskToClear(try fixture.field(.left))
    #expect(!button.isEnabled)
  }

  @Test(arguments: [2, 3])
  func defaultButtonOpensExactlyTheShownRoles(fileCount: Int) async throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture(fileCount == 3 ? .merge : .compare)
    let urls = try (1...fileCount).map { try files.file("\($0).txt") }
    #expect(fixture.controller.fill(with: urls))
    fixture.controller.swapSides(nil)

    fixture.controller.openButton.performClick(nil)
    #expect(!fixture.controller.openButton.isEnabled)
    await fixture.opener.nextOpening()

    let opened = try #require(fixture.opener.opened.first)
    #expect(opened.left == urls[urls.count - 1])
    #expect(opened.base == (fileCount == 3 ? urls[1] : nil))
    #expect(opened.right == urls[0])
    #expect(opened.kind == (fileCount == 3 ? .merge : .diff))
  }

  @Test func filesThatCannotBeOpenedStayWithTheirReason() async throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture(.merge)
    let urls = [try files.file("a.txt"), try files.file("o.txt"), try files.file("b.png")]
    fixture.opener.failure = SessionLoadingError.binaryFile(urls[2])
    #expect(fixture.controller.fill(with: urls))

    fixture.controller.openButton.performClick(nil)
    await fixture.opener.nextOpening()

    #expect(fixture.panels.failures == ["“b.png” isn’t a text file."])
    #expect(fixture.files == urls)
    #expect(fixture.controller.openButton.isEnabled)
  }

  @Test func everyFieldIsFilledAndClearedFromTheKeyboard() async throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture(.merge)
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
    #expect(fixture.panels.roles == ["A", "Base", "B"])
    #expect(fixture.panels.fileChoices == [.file, .file, .file])
  }

  @Test func tabRunsThroughTheFieldsFromLeftToRight() throws {
    let fixture = CompareFilesFixture(.merge)
    fixture.window.makeFirstResponder(try fixture.field(.left))

    var order: [NSResponder?] = [fixture.window.firstResponder]
    for _ in 1...2 {
      fixture.window.selectNextKeyView(nil)
      order.append(fixture.window.firstResponder)
    }

    #expect(order == (try FileSlot.allCases.map { try fixture.field($0) }))
  }

  @Test func focusGoesToTheFirstEmptyField() throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture(.merge)
    #expect(
      fixture.controller.acceptDrop(DragInTest(files: [try files.file("a.txt")]), onto: .left))

    fixture.controller.focusFirstEmptyField()

    #expect(fixture.window.firstResponder === (try fixture.field(.base)))
  }

  @Test func everyFieldTellsVoiceOverItsRoleAndContent() throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture()
    let left = try files.file("LoginView.swift")
    let folder = FileField.folderName(of: left)

    var labels = try [FileSlot.left, .right].map { try fixture.field($0).accessibilityLabel() }
    var values = try [FileSlot.left, .right].map {
      try fixture.field($0).accessibilityValue() as? String
    }
    #expect(labels == ["Left", "Right"])
    #expect(values == ["empty", "empty"])
    #expect(try fixture.field(.left).accessibilityRole() == .button)
    #expect(
      try fixture.field(.left).accessibilityHelp() == "Choose a file or folder, or drop one here")

    #expect(fixture.controller.acceptDrop(DragInTest(files: [left]), onto: .left))
    labels = try [FileSlot.left, .right].map { try fixture.field($0).accessibilityLabel() }
    values = try [FileSlot.left, .right].map {
      try fixture.field($0).accessibilityValue() as? String
    }
    #expect(labels == ["Left", "Right"])
    #expect(values == ["LoginView.swift, in \(folder)", "empty"])
    #expect(fixture.announcements == ["LoginView.swift added as Left"])

    let merge = CompareFilesFixture(.merge)
    #expect(
      try FileSlot.allCases.map { try merge.field($0).accessibilityLabel() } == ["A", "Base", "B"])
    #expect(try merge.field(.left).accessibilityHelp() == "Choose a file, or drop one here")
  }

  @Test func emptyingAFieldIsAnnouncedAndWorksForVoiceOver() throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture()
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
    let fixture = CompareFilesFixture()
    let url = try files.file("a.txt")
    #expect(fixture.controller.fill(with: [url]))

    #expect(try fixture.field(.left).toolTip == url.path(percentEncoded: false))
    #expect(try fixture.field(.right).toolTip == nil)
  }

  @Test func changeFilesKeepsTheKindOfItsWindow() throws {
    let files = try SampleFiles()
    let fixture = CompareFilesFixture(.change(.merge))
    let comparison = FileComparison(
      left: try files.file("a.txt"), base: try files.file("o.txt"), right: try files.file("b.txt"))
    fixture.controller.fill(comparison)
    #expect(fixture.controller.openButton.isEnabled)

    fixture.controller.clear(.base)

    #expect(!fixture.controller.openButton.isEnabled)
    #expect(try fixture.field(.left).accessibilityHelp() == "Choose a file, or drop one here")
  }
}
