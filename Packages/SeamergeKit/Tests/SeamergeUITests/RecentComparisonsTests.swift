import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// The comparisons opened last: what the list keeps, and how the window shows and opens them.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct RecentComparisonsTests {
  @Test func listKeepsTheTenNewestFirstWithTheirRoles() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let comparisons = try (1...12).map { number in
      FileComparison(
        left: try files.file("\(number)-a.txt"),
        base: number.isMultiple(of: 2) ? try files.file("\(number)-base.txt") : nil,
        right: try files.file("\(number)-b.txt"))
    }

    for comparison in comparisons {
      fixture.recentComparisons.add(comparison)
    }
    fixture.recentComparisons.add(comparisons[5])

    let kept = fixture.recentComparisons.comparisons
    #expect(kept.count == RecentComparisons.maximumCount)
    #expect(kept.first == comparisons[5])
    let older = comparisons.reversed().filter { $0 != comparisons[5] }
    #expect(Array(kept.dropFirst()) == Array(older.prefix(9)))
  }

  @Test func comparisonWhoseFileIsGoneIsLeftOut() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let kept = FileComparison(left: try files.file("a.txt"), right: try files.file("b.txt"))
    let gone = try files.file("gone.txt")
    fixture.recentComparisons.add(FileComparison(left: kept.left, base: gone, right: kept.right))
    fixture.recentComparisons.add(kept)

    try FileManager.default.removeItem(at: gone)

    #expect(fixture.recentComparisons.comparisons == [kept])
  }

  @Test func windowListsTheFiveNewestAndHidesTheListWithoutAny() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let list = fixture.controller.recentList
    #expect(list.scrollView.superview?.isHidden == true)

    for number in 1...7 {
      fixture.recentComparisons.add(
        FileComparison(left: try files.file("\(number).txt"), right: try files.file("new.txt")))
    }

    #expect(list.scrollView.superview?.isHidden == false)
    #expect(
      list.comparisons.map(\.left.lastPathComponent) == [
        "7.txt", "6.txt", "5.txt", "4.txt", "3.txt",
      ])

    fixture.recentComparisons.clear()
    #expect(list.scrollView.superview?.isHidden == true)
    #expect(list.comparisons.isEmpty)
  }

  @Test func listIsAsHighAsItsLinesAndTheOpenWindowKeepsItsHeight() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let emptyHeight = fixture.window.frame.height
    let rowHeight = fixture.controller.recentList.tableView.rowHeight
    for number in 1...2 {
      fixture.recentComparisons.add(
        FileComparison(left: try files.file("\(number).txt"), right: try files.file("new.txt")))
    }
    let twoLinesHeight = fixture.window.frame.height
    #expect(fixture.controller.recentList.scrollView.frame.height < 3 * rowHeight)
    #expect(twoLinesHeight > emptyHeight)

    fixture.controller.showWindow(nil)
    fixture.recentComparisons.clear()

    #expect(fixture.window.frame.height == twoLinesHeight)
    fixture.window.close()
    fixture.controller.showWindow(nil)
    #expect(fixture.window.frame.height == emptyHeight)
    fixture.window.close()
  }

  @Test func lineOfTheListNamesTheFilesInTheOrderOfTheirRoles() throws {
    let files = try SampleFiles()
    let merge = FileComparison(
      left: try files.file("Theirs.json"), base: try files.file("Base.json"),
      right: try files.file("Mine.json"))
    let comparison = FileComparison(
      left: try files.file("LoginView.swift"), right: try files.file("LoginView copy.swift"))

    #expect(comparison.title == "LoginView.swift ↔ LoginView copy.swift")
    #expect(merge.title == "Theirs.json ↔ Base.json ↔ Mine.json")
    #expect(comparison.accessibilityTitle == "Compare LoginView.swift with LoginView copy.swift")
    #expect(merge.accessibilityTitle == "Merge Theirs.json and Mine.json with the base Base.json")
    #expect(merge.folder == FileField.folderName(of: merge.left))
  }

  @Test func folderOfFilesInDifferentFoldersIsTheOneTheyShare() throws {
    let comparison = FileComparison(
      left: URL(filePath: "/Users/someone/Projects/app/Sources/A.swift"),
      right: URL(filePath: "/Users/someone/Projects/app/Tests/A.swift"))

    #expect(comparison.folder == "/Users/someone/Projects/app")
  }

  @Test func returnOpensTheSelectedComparison() async throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let comparison = FileComparison(
      left: try files.file("a.txt"), base: try files.file("o.txt"), right: try files.file("b.txt"))
    fixture.recentComparisons.add(comparison)
    let table = fixture.controller.recentList.tableView
    table.selectRowIndexes([0], byExtendingSelection: false)
    fixture.window.makeFirstResponder(table)

    #expect(fixture.window.performKeyEquivalent(with: try fixture.key("\r")))
    await fixture.delegate.nextOpening()

    #expect(fixture.delegate.opened == [comparison])
    #expect(!fixture.controller.openButton.isEnabled)
  }

  @Test func returnElsewhereGoesToTheDefaultButton() async throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    fixture.recentComparisons.add(
      FileComparison(left: try files.file("x.txt"), right: try files.file("y.txt")))
    let comparison = FileComparison(left: try files.file("a.txt"), right: try files.file("b.txt"))
    #expect(fixture.controller.fill(with: comparison.files))
    fixture.window.makeFirstResponder(try fixture.field(.left))

    #expect(fixture.window.performKeyEquivalent(with: try fixture.key("\r")))
    await fixture.delegate.nextOpening()

    #expect(fixture.delegate.opened == [comparison])
  }

  @Test func lineOfTheListTellsVoiceOverWhatItOpens() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    fixture.recentComparisons.add(
      FileComparison(left: try files.file("a.txt"), right: try files.file("b.txt")))
    let table = fixture.controller.recentList.tableView

    let cell = try #require(table.view(atColumn: 0, row: 0, makeIfNecessary: true))

    #expect(cell.accessibilityLabel() == "Compare a.txt with b.txt")
  }
}
