import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// The comparisons opened last: what the list keeps, and how the welcome window shows and opens
/// them.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct RecentComparisonsTests {
  @Test func listKeepsTheTenNewestFirstWithTheirRoles() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
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
    let fixture = try WelcomeFixture()
    let kept = FileComparison(left: try files.file("a.txt"), right: try files.file("b.txt"))
    let gone = try files.file("gone.txt")
    fixture.recentComparisons.add(FileComparison(left: kept.left, base: gone, right: kept.right))
    fixture.recentComparisons.add(kept)

    try FileManager.default.removeItem(at: gone)

    #expect(fixture.recentComparisons.comparisons == [kept])
  }

  @Test func windowListsTheFiveNewestAndHidesTheListWithoutAny() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
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

  @Test func windowKeepsItsSizeWhateverTheList() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let size = fixture.window.contentView?.frame.size
    #expect(size == WelcomeMetrics.contentSize)

    for number in 1...7 {
      fixture.recentComparisons.add(
        FileComparison(left: try files.file("\(number).txt"), right: try files.file("new.txt")))
    }
    fixture.controller.showWindow(nil)
    #expect(fixture.window.contentView?.frame.size == size)
    fixture.recentComparisons.clear()
    #expect(fixture.window.contentView?.frame.size == size)
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

  @Test func returnOpensTheSelectedComparisonWhichComesFirstOnceItShows() async throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let comparison = FileComparison(
      left: try files.file("a.txt"), base: try files.file("o.txt"), right: try files.file("b.txt"))
    let other = FileComparison(left: try files.file("x.txt"), right: try files.file("y.txt"))
    fixture.recentComparisons.add(comparison)
    fixture.recentComparisons.add(other)
    fixture.controller.showWindow(nil)
    let table = fixture.controller.recentList.tableView
    table.selectRowIndexes([1], byExtendingSelection: false)
    fixture.window.makeFirstResponder(table)

    #expect(fixture.window.performKeyEquivalent(with: try keyEvent("\r", in: fixture.window)))
    await fixture.opener.nextOpening()
    await fixture.nextClose()

    #expect(fixture.opener.opened == [comparison])
    #expect(fixture.recentComparisons.comparisons == [comparison, other])
  }

  @Test func returnElsewhereGoesToTheDefaultButton() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    fixture.recentComparisons.add(
      FileComparison(left: try files.file("x.txt"), right: try files.file("y.txt")))
    fixture.controller.showWindow(nil)
    fixture.window.makeFirstResponder(nil)

    #expect(fixture.window.performKeyEquivalent(with: try keyEvent("\r", in: fixture.window)))

    #expect(try fixture.sheet().purpose == .compare)
    #expect(fixture.opener.opened.isEmpty)
  }

  @Test func comparisonThatCannotBeOpenedFromTheListStandsInItsSheet() async throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let comparison = FileComparison(left: try files.file("a.png"), right: try files.file("b.txt"))
    fixture.recentComparisons.add(comparison)
    fixture.opener.failure = SessionLoadingError.binaryFile(comparison.left)

    fixture.controller.open(comparison)
    await fixture.panels.nextFailure()

    #expect(try fixture.sheet().selection.comparison == comparison)
    #expect(fixture.panels.failures == ["“a.png” isn’t a text file."])
  }

  @Test func lineOfTheListTellsVoiceOverWhatItOpens() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    fixture.recentComparisons.add(
      FileComparison(left: try files.file("a.txt"), right: try files.file("b.txt")))
    let table = fixture.controller.recentList.tableView

    let cell = try #require(table.view(atColumn: 0, row: 0, makeIfNecessary: true))

    #expect(cell.accessibilityLabel() == "Compare a.txt with b.txt")
  }
}
