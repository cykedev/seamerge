import AppKit
import MergeModel
import PaneKit
import SyntaxKit
import Testing

@testable import SeamergeUI

/// The phases that every large case goes through, in the order that keeps them comparable with
/// earlier measurements: each phase starts in the state the one before left.
extension LargeFileRun {
  /// Waits until the window has the tokens of every file and has colored them, then measures the
  /// layout and the picture with the colors; next, lexing one file alone, for comparison.
  func measureColoring(since start: ContinuousClock.Instant) async throws {
    let syntax = controller.presentation.syntax
    let session = controller.presentation.changes.session
    guard syntax.language != nil else { return }
    let isColored = { session.roles.allSatisfy { syntax.tokens(of: $0) != nil } }
    // The lexing began with the window, but its results come in on the main actor, which this
    // has held since; the observer is in place before the first of them.
    if !isColored() {
      let lexed = syntax.onLexed
      defer { syntax.onLexed = lexed }
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        var waiting: CheckedContinuation<Void, Never>? = continuation
        syntax.onLexed = {
          lexed()
          if isColored() {
            waiting?.resume()
            waiting = nil
          }
        }
      }
    }
    recorder.record("syntax-window", clock.now - start)
    contentView.layoutSubtreeIfNeeded()
    draw()
    recorder.record("syntax-window-drawn", clock.now - start)

    let text = session.file(for: .b)?.text ?? ""
    let language = LanguageDescription(fileName: "file.\(largeCase.fileExtension)")
    let lexing = clock.measure {
      _ = LexedText(
        language: language, lines: text.split(separator: "\n", omittingEmptySubsequences: false))
    }
    recorder.record("syntax-lex-one-file", lexing)
  }

  /// Measures the word marks of every changed block, as if each came into view once.
  func measureWordMarks() throws {
    let session = controller.presentation.changes.session
    var total = Duration.zero
    var longest = Duration.zero
    for block in session.blocks where block.kind != .unchanged {
      let duration = try clock.measure { _ = try session.inlineHighlights(for: block) }
      total += duration
      longest = max(longest, duration)
    }
    recorder.record("wordmarks-total", total)
    recorder.record("wordmarks-max-block", longest)
  }

  /// Measures the jumps between changes: to the last and the first, then back one at a time
  /// from the last and forward from the first, at most once to each change, so that the window
  /// ends on the 21st change or the last, where the next phases begin.
  func measureJumps() {
    measure(
      "jump-last-change", .few, prepare: { controller.perform(.firstChange) },
      action: { controller.perform(.lastChange) })
    measure(
      "jump-first-change", .few, prepare: { controller.perform(.lastChange) },
      action: { controller.perform(.firstChange) })
    let changes = controller.presentation.changes.blocks.count
    var steps = Repetitions.steps
    steps.most = min(steps.most, max(1, changes - 1))
    controller.perform(.lastChange)
    measure("jump-previous-change", steps) { controller.perform(.previousChange) }
    controller.perform(.firstChange)
    measure("jump-next-change", steps) { controller.perform(.nextChange) }
  }

  /// Shows all lines, collapses the unchanged ones again and shows all lines once more; the
  /// second time the window shows all lines, TextKit has laid out much of it before, which the
  /// metric names with `-repeated`.
  func measureShowingAllLines() {
    measure("show-all-lines", .once) { controller.perform(.showAllLines) }
    measure("collapse-unchanged-lines", .once) { controller.perform(.collapseUnchangedLines) }
    measure("show-all-lines-repeated", .once) { controller.perform(.showAllLines) }
  }

  /// Measures switching to Connected Sides, to Single Column where the window has it, and
  /// back to Aligned Lines, once each.
  ///
  /// Once only, since every switch leaves the window slower to compare anew afterwards (about
  /// 8 ms per switch at 10,000 lines) and the phases after it are to be measured as after a
  /// user's few switches; the runs of the script give the repetitions.
  func measureArrangements() {
    let arrangements: [(String, SessionCommand)] = [
      ("switch-connected", .showConnectedSides), ("switch-single-column", .showSingleColumn),
      ("switch-aligned", .showAlignedLines),
    ]
    for (metric, command) in arrangements where isAvailable(command) {
      measure(metric, .once) { controller.perform(command) }
    }
  }

  /// Whether the window can carry out `command` now, as its menu item would show.
  func isAvailable(_ command: SessionCommand) -> Bool {
    let item = NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
    return controller.validateUserInterfaceItem(item)
  }

  /// Switches to comparing exactly, which compares anew and replaces what the window shows,
  /// and measures it until the window is laid out and drawn, with the longest hold of the main
  /// actor meanwhile.
  func measureSwitchingTheMode() async {
    var options = controller.comparisonOptions
    options.mode = .exact
    let start = clock.now
    let held = await longestHold {
      await controller.switchComparison(to: options)
      contentView.layoutSubtreeIfNeeded()
    }
    recorder.record("mode-switch-exact", clock.now - start)
    draw()
    recorder.record("mode-switch-exact-drawn", clock.now - start)
    recorder.record("mode-switch-exact-longest-hold", held)
  }

  /// Searches all panes for a rare text, then for a common one, each until the first matches
  /// and until all of them, with the longest hold of the main actor meanwhile, and closes the
  /// find bar.
  ///
  /// A search that does not find all its matches within `limit` ends the searching, since
  /// typing while the finder searches races with that search.
  func measureSearching(limit: Duration = .seconds(120)) async throws {
    try await FindPasteboard.preserving {
      let driver = SearchDriver(controller)
      #expect(try driver.send(.find))
      let texts = largeCase.searchTexts
      for (label, text) in [("rare", texts.rare), ("common", texts.common)] {
        let expected = matchCount(of: text)
        // An empty field drops the matches of the search before, so that the first matches
        // counted are those of this search.
        if !driver.search.matches.isEmpty {
          try driver.type("")
          guard await waitForMatches(of: driver, until: clock.now + limit, { $0 == 0 }) else {
            Issue.record("The matches of the search before stayed")
            return
          }
        }
        let start = clock.now
        var found = false
        let held = try await longestHold {
          try driver.type(text)
          found = await waitForMatches(of: driver, until: start + limit) { $0 > 0 }
          if found {
            recorder.record("search-\(label)-first", clock.now - start)
          }
          found = await waitForMatches(of: driver, until: start + limit) { $0 >= expected }
        }
        recorder.record(found ? "search-\(label)" : "search-\(label)-timeout", clock.now - start)
        recorder.record(
          "search-\(label)-matches", Double(driver.search.matches.count), unit: "matches")
        recorder.record("search-\(label)-expected", Double(expected), unit: "matches")
        recorder.record("search-\(label)-longest-hold", held)
        guard found else { return }
      }
      measure("search-hide", .once) { driver.search.perform(.hideFindInterface) }
    }
  }

  /// How often `text` occurs in what the search goes through: the files of the source panes it
  /// searches, in full, also lines that the panes show cut short, and the text of the result
  /// pane, if it searches that, without the previews of open conflicts.
  private func matchCount(of text: String) -> Int {
    let presentation = controller.presentation
    let searched = presentation.searchedPanes
    let session = presentation.changes.session
    var pieces = controller.layout.sourcePanes.filter { source in
      searched.contains { $0 === source.pane }
    }.map { source -> (NSString, NSRange) in
      let fileText = (session.file(for: source.role)?.text ?? "") as NSString
      return (fileText, NSRange(location: 0, length: fileText.length))
    }
    if let resultPane = controller.layout.resultPane,
      searched.contains(where: { $0 === resultPane })
    {
      let paneText = resultPane.documentView.string as NSString
      var start = 0
      for preview in resultPane.content.previews.map(\.range).sorted(by: {
        $0.lowerBound < $1.lowerBound
      }) {
        pieces.append((paneText, NSRange(location: start, length: preview.lowerBound - start)))
        start = preview.upperBound
      }
      pieces.append((paneText, NSRange(location: start, length: paneText.length - start)))
    }
    return pieces.reduce(0) { count, piece in
      let (pieceText, pieceRange) = piece
      var count = count
      var range = pieceRange
      while true {
        let match = pieceText.range(of: text, options: .caseInsensitive, range: range)
        guard match.location != NSNotFound else { return count }
        count += 1
        range = NSRange(
          location: match.upperBound, length: NSMaxRange(pieceRange) - match.upperBound)
      }
    }
  }

  /// Waits until the number of matches satisfies `condition`, or until `deadline`.
  ///
  /// - Returns: Whether the condition holds.
  private func waitForMatches(
    of driver: SearchDriver, until deadline: ContinuousClock.Instant,
    _ condition: @escaping (Int) -> Bool
  ) async -> Bool {
    let search = driver.search
    let waiting = Task { @MainActor in
      await driver.waitForMatches { condition(search.matches.count) }
    }
    // The deadline only bounds the wait; the matches themselves end it as soon as they are in.
    let timeout = Task {
      try await ContinuousClock().sleep(until: deadline)
      waiting.cancel()
    }
    await waiting.value
    timeout.cancel()
    return condition(search.matches.count)
  }
}
