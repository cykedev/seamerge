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

  @Test func windowListsEveryKeptComparisonAndNamesTheNextStepWithoutAny() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let list = fixture.controller.recentList
    let empty = fixture.controller.emptyListView
    #expect(list.scrollView.isHidden)
    #expect(!empty.isHidden)
    #expect(
      empty.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue } == [
        "No Recent Comparisons", "Choose Compare Files… or drop two files on this window.",
      ])
    // Quiet text that reaches 4.5 : 1, which the secondary label color does not in light mode.
    let light = try #require(NSAppearance(named: .aqua))
    let quietText = Contrast.resolve(CompareFilesColors(DisplayOptions()).quietText, in: light)
    for case let label as NSTextField in empty.arrangedSubviews {
      #expect(Contrast.resolve(label.textColor, in: light) == quietText)
    }

    for number in 1...12 {
      fixture.recentComparisons.add(
        FileComparison(left: try files.file("\(number).txt"), right: try files.file("new.txt")))
    }

    #expect(!list.scrollView.isHidden)
    #expect(empty.isHidden)
    #expect(
      list.comparisons.map(\.left.lastPathComponent)
        == (3...12).reversed().map { "\($0).txt" })

    fixture.recentComparisons.clear()
    #expect(list.scrollView.isHidden)
    #expect(!empty.isHidden)
    #expect(list.comparisons.isEmpty)
  }

  @Test func listGroupsTodayAndEarlierWithTheTimeOrTheDay() throws {
    let files = try SampleFiles()
    let list = RecentComparisonsList()
    list.calendar = Self.calendar
    let now = try Self.date("2026-11-17T15:30:00Z")
    let entries = [
      RecentComparisons.Entry(
        comparison: FileComparison(left: try files.file("a.txt"), right: try files.file("b.txt")),
        opened: try Self.date("2026-11-17T09:05:00Z")),
      RecentComparisons.Entry(
        comparison: FileComparison(
          left: try files.file("x.txt"), base: try files.file("o.txt"),
          right: try files.file("y.txt")),
        opened: try Self.date("2026-11-16T23:59:00Z")),
      RecentComparisons.Entry(
        comparison: FileComparison(left: try files.file("c.txt"), right: try files.file("d.txt")),
        opened: nil),
    ]

    list.show(entries, now: now)

    #expect(
      list.rows == [
        .heading("Today"), .comparison(entries[0]), .heading("Earlier"), .comparison(entries[1]),
        .comparison(entries[2]),
      ])
    #expect(list.tableView(list.tableView, isGroupRow: 0))
    #expect(!list.tableView(list.tableView, shouldSelectRow: 0))
    #expect(list.tableView(list.tableView, shouldSelectRow: 1))
    // The format of the system puts a narrow no-break space before AM.
    #expect(list.dateText(of: entries[0].opened) == "9:05\u{202F}AM")
    #expect(list.dateText(of: entries[1].opened) == "Nov 16, 2026")
    #expect(list.dateText(of: nil).isEmpty)
  }

  @Test func lineShowsTheKindTheNamesTheFolderAndTheTime() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let folder = FileField.folderName(of: try files.file("a.txt"))
    let merge = FileComparison(
      left: try files.file("Theirs.json"), base: try files.file("Base.json"),
      right: try files.file("Mine.json"))
    let folders = FileComparison(
      folders: FolderPair(left: try files.subfolder("old"), right: try files.subfolder("new")))
    let comparison = FileComparison(
      left: try files.file("LoginView.swift"), right: try files.file("LoginView copy.swift"))
    for added in [merge, folders, comparison] {
      fixture.recentComparisons.add(added)
    }
    let table = fixture.controller.recentList.tableView

    let cells = try (1...3).map { row in
      try #require(
        table.view(atColumn: 0, row: row, makeIfNecessary: true) as? RecentComparisonCell)
    }

    #expect(cells.map(\.namesLabel.stringValue) == [comparison, folders, merge].map(\.title))
    #expect(
      cells.map(\.kindLabel.stringValue) == ["Comparison ·", "Folder Comparison ·", "Merge ·"])
    #expect(cells.allSatisfy { $0.folderLabel.stringValue == folder })
    #expect(
      [comparison, folders, merge].map(\.symbolName) == [
        "doc.on.doc", "folder", "arrow.triangle.merge",
      ])
    #expect(cells.allSatisfy { $0.symbolView.image != nil })
    #expect(
      cells.allSatisfy {
        $0.namesLabel.font?.fontDescriptor.symbolicTraits.contains(.bold) == true
      })
    #expect(cells.allSatisfy { !$0.dateLabel.stringValue.isEmpty })
  }

  @Test func comparisonKeptWithoutItsTimeIsListedUnderEarlier() throws {
    let files = try SampleFiles()
    let name = "SeamergeUITests.\(UUID().uuidString)"
    let defaults = UserDefaults.privateSuite(named: name)
    defer { defaults.removePersistentDomain(forName: name) }
    let (left, right) = (try files.file("a.txt"), try files.file("b.txt"))
    defaults.set(
      [["left": left.path(percentEncoded: false), "right": right.path(percentEncoded: false)]],
      forKey: "RecentComparisons")
    let list = RecentComparisonsList()

    list.show(RecentComparisons(defaults: defaults).entries)

    let entry = RecentComparisons.Entry(
      comparison: FileComparison(left: left, right: right), opened: nil)
    #expect(list.rows == [.heading("Earlier"), .comparison(entry)])
  }

  @Test func timeOfAnOpeningIsKept() throws {
    let files = try SampleFiles()
    let name = "SeamergeUITests.\(UUID().uuidString)"
    let defaults = UserDefaults.privateSuite(named: name)
    defer { defaults.removePersistentDomain(forName: name) }
    let comparison = FileComparison(left: try files.file("a.txt"), right: try files.file("b.txt"))
    let opened = try Self.date("2026-11-17T09:05:00Z")

    RecentComparisons(defaults: defaults).add(comparison, openedAt: opened)

    #expect(
      RecentComparisons(defaults: defaults).entries == [
        .init(comparison: comparison, opened: opened)
      ])
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
    table.selectRowIndexes([2], byExtendingSelection: false)
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

  @Test func lineOfTheListTellsVoiceOverWhatItOpensAndWhen() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let comparison = FileComparison(left: try files.file("a.txt"), right: try files.file("b.txt"))
    fixture.recentComparisons.add(comparison)
    let list = fixture.controller.recentList

    let cell = try #require(list.tableView.view(atColumn: 0, row: 1, makeIfNecessary: true))

    #expect(cell.accessibilityLabel() == "Compare a.txt with b.txt")
    let time = list.dateText(of: try #require(fixture.recentComparisons.entries.first?.opened))
    #expect(cell.accessibilityValue() as? String == "\(comparison.folder), \(time)")
  }

  /// A calendar of fixed place and language, so that times read the same on every Mac.
  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    calendar.locale = Locale(identifier: "en_US")
    return calendar
  }

  private static func date(_ text: String) throws -> Date {
    try Date(text, strategy: .iso8601)
  }
}
