import AppKit
import Testing

@testable import PaneKit

/// Checks the search over several panes as the finder sees it: the text it reads, the order of
/// the matches, the panes that show them, the selection, and replacing through the editing
/// delegate, without the finder itself, which shares its search text with the whole system.
@MainActor
@Suite struct PaneSearchTests {
  /// A match as the expectations name it: the pane and the range in its text.
  struct Place: Equatable, CustomStringConvertible {
    var pane: String
    var range: Range<Int>

    var description: String { "\(pane) \(range)" }
  }

  /// Brings every occurrence of `needle` into view in the order of the search text, as Find Next
  /// would, and returns where the search's delegate saw them.
  private func revealAll(_ needle: String, in panes: SearchPanes) -> [Place] {
    for range in panes.occurrences(of: needle) {
      panes.search.scrollRangeToVisible(range)
    }
    return panes.observer.revealed.map { Place(pane: panes.name(of: $0.pane), range: $0.range) }
  }

  @Test func matchesFollowTheOrderOfTheSectionsThatTheOwnerGave() {
    let panes = SearchPanes()
    defer { panes.window.close() }
    #expect(
      revealAll("needle", in: panes) == [
        Place(pane: "A", range: 6..<12), Place(pane: "A", range: 13..<19),
        Place(pane: "Base", range: 0..<6), Place(pane: "Result", range: 0..<6),
        Place(pane: "A", range: 21..<27), Place(pane: "Base", range: 21..<27),
        Place(pane: "Result", range: 34..<40),
      ])
  }

  @Test func lineFeedsHoldTheLinesApartSoNoMatchReachesAcrossALineOrAPane() {
    let panes = SearchPanes()
    defer { panes.window.close() }
    #expect(
      panes.search.string
        == "alpha needle\nneedle\nneedle\nneedle\nneedle tail\nneedle\npre \n post\nend needle")
    // The end of one line and the start of the next, within a pane and from pane to pane.
    #expect(panes.occurrences(of: "needleneedle").isEmpty)
    #expect(panes.occurrences(of: "tailneedle").isEmpty)
    #expect(panes.occurrences(of: "needlepre").isEmpty)
    // Both sides of the preview within the third row of the result.
    #expect(panes.occurrences(of: "  ").isEmpty)
  }

  @Test func matchThatHoldsALineFeedBelongsToNoPaneAndFindNextGoesOnAfterIt() throws {
    let panes = SearchPanes()
    defer { panes.window.close() }
    // A pattern that matches any whitespace, as a search for a line break might.
    let pattern = try NSRegularExpression(pattern: "alpha needle\\sneedle")
    let text = panes.search.string as NSString
    #expect(text.length == 74)
    let found = try #require(
      pattern.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)))
    #expect(found.range == NSRange(location: 0, length: 19))
    panes.search.scrollRangeToVisible(found.range)
    #expect(panes.observer.revealed.isEmpty)
    #expect(panes.search.rects(forCharacterRange: found.range) == nil)
    panes.search.selectedRanges = [NSValue(range: found.range)]
    #expect(panes.a.documentView.selectedRange() == NSRange(location: 19, length: 0))
    // Any character never matches a line feed.
    let anyCharacter = try NSRegularExpression(pattern: "needle.needle")
    #expect(
      anyCharacter.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length))
        == nil)
  }

  @Test func replaceAllReplacesTheMatchesOfAPaneAndLeavesThoseAcrossALine() {
    let panes = SearchPanes()
    defer { panes.window.close() }
    panes.search.scope = .pane(panes.result)
    #expect((panes.search.string as NSString).length == 28)
    // The result alone: "needle" 0..<6; "pre " 7..<11, " post" 12..<17, "end needle" 18..<28,
    // with line feeds between them; "post\nend" reaches across a line.
    let across = NSRange(location: 13, length: 8)
    let needle = NSRange(location: 22, length: 6)
    #expect(
      panes.search.shouldReplaceCharacters(
        inRanges: [NSValue(range: across), NSValue(range: needle)], with: ["x", "pin"]))
    panes.search.replaceCharacters(in: needle, with: "pin")
    panes.search.replaceCharacters(in: across, with: "x")
    panes.search.didReplaceCharacters()
    #expect(panes.result.documentView.string == "needle\nneedle\npre needle post\nend pin")
    // A replacement of matches across lines alone is refused.
    #expect(!panes.search.shouldReplaceCharacters(inRanges: [NSValue(range: across)], with: ["x"]))
  }

  @Test func longTextReadsAsItsLinesAndEveryLineKeepsItsPlace() {
    let lines = (0..<100_000).map { "line \($0)" }
    let text = lines.joined(separator: "\n")
    var offset = 0
    let ranges = lines.map { line -> Range<Int> in
      defer { offset += line.utf16.count + 1 }
      return offset..<offset + line.utf16.count
    }
    let search = SearchText(
      texts: [text as NSString],
      sections: [SearchText.Section(pane: 0, lines: ranges, excluded: [])])

    #expect(search.string == text)
    for line in [0, 1, 4_242, 99_999] {
      let place = search.searchRange(ofPaneRange: ranges[line], inPane: 0)
      #expect(place.flatMap(search.paneRange(of:))?.range == ranges[line], "\(line)")
    }
  }

  /// The search text of the lines of one pane whose text is `text`, without previews unless
  /// `excluded` names some.
  private func searchText(
    of text: String, lines: [Range<Int>], excluded: [Range<Int>] = []
  ) -> SearchText {
    SearchText(
      texts: [text as NSString],
      sections: [SearchText.Section(pane: 0, lines: lines, excluded: excluded)])
  }

  @Test func linesThatFollowEachOtherAreOnePieceThatEmptyLinesNeitherStartNorEnd() {
    let lines = [0..<0, 1..<2, 3..<4, 5..<5, 6..<6, 7..<8, 9..<9]
    let search = searchText(of: "\na\nb\n\n\nc\n", lines: lines)
    #expect(search.pieces.map(\.paneRange) == [1..<8])
    #expect(search.string == "a\nb\n\n\nc")
    #expect(search.paneRange(of: 6..<7)?.range == 7..<8)
  }

  @Test func rowLeftOutOrPreviewEndsAPiece() {
    // The second row, a filler row, is left out; the fourth has a preview at its start.
    let search = searchText(
      of: "ab\nfill\ncd\nef\ngh", lines: [0..<2, 8..<10, 11..<13, 14..<16],
      excluded: [11..<12])
    #expect(search.pieces.map(\.paneRange) == [0..<2, 8..<10, 12..<16])
    #expect(search.string == "ab\ncd\nf\ngh")
  }

  @Test func matchOfSeveralLinesWithinOnePieceBelongsToNoPane() {
    let search = searchText(of: "needle\nneedle", lines: [0..<6, 7..<13])
    #expect(search.pieces.count == 1)
    #expect(search.paneRange(of: 3..<10) == nil)
    #expect(search.paneRange(of: 6..<6)?.range == 6..<6)
    #expect(search.paneRange(of: 7..<13)?.range == 7..<13)
  }

  @Test func fillerRowsAndPreviewsAreNeverSearched() {
    let panes = SearchPanes()
    defer { panes.window.close() }
    #expect(panes.occurrences(of: "filler").isEmpty)
    let inResult = revealAll("needle", in: panes).filter { $0.pane == "Result" }
    // The preview of the second row and the one in the middle of the third hold "needle" too.
    #expect(inResult.map(\.range) == [0..<6, 34..<40])
  }

  @Test func searchTextFollowsEveryChangeOfThePanesText() {
    let panes = SearchPanes()
    defer { panes.window.close() }
    #expect(panes.occurrences(of: "needle").count == 7)
    // Typing at the end of the result, through its editing delegate.
    panes.window.makeFirstResponder(panes.result.documentView)
    panes.result.documentView.setSelectedRange(NSRange(location: 40, length: 0))
    panes.result.documentView.insertText(
      " needle", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(panes.occurrences(of: "needle").count == 8)
    // New content in A, as its owner gives it.
    panes.a.content = PaneContent(text: "nothing here", lineNumbers: [0])
    #expect(panes.occurrences(of: "needle").count == 5)
    #expect(panes.search.string.hasPrefix("nothing here\n"))
  }

  @Test func scopeOfOnePaneSearchesItsSectionsAloneAndAllowsReplacingIfItIsEditable() {
    let panes = SearchPanes()
    defer { panes.window.close() }
    #expect(!panes.search.isEditable)
    panes.search.scope = .pane(panes.result)
    #expect(panes.search.isEditable)
    #expect(
      revealAll("needle", in: panes) == [
        Place(pane: "Result", range: 0..<6), Place(pane: "Result", range: 34..<40),
      ])
    panes.search.scope = .pane(panes.base)
    #expect(!panes.search.isEditable)
    panes.search.scope = .allPanes
    #expect(panes.occurrences(of: "needle").count == 7)
  }

  @Test func replacingIsRefusedUnlessTheSearchIsLimitedToAnEditablePane() {
    let panes = SearchPanes()
    defer { panes.window.close() }
    let ranges = panes.occurrences(of: "needle").map { NSValue(range: $0) }
    #expect(!panes.search.shouldReplaceCharacters(inRanges: ranges, with: ["pin"]))
    panes.search.replaceCharacters(in: ranges[3].rangeValue, with: "pin")
    #expect(panes.editor.asked.isEmpty)
    #expect(panes.observer.replacements.isEmpty)
    #expect(panes.result.documentView.string == SearchPanes.resultText)
  }

  @Test func replacingAMatchGoesThroughTheEditingDelegateOfItsPaneAlone() throws {
    let panes = SearchPanes()
    defer { panes.window.close() }
    panes.search.scope = .pane(panes.result)
    let last = try #require(panes.occurrences(of: "needle").last)
    #expect(panes.search.shouldReplaceCharacters(inRanges: [NSValue(range: last)], with: ["pin"]))
    panes.search.replaceCharacters(in: last, with: "pin")
    panes.search.didReplaceCharacters()
    #expect(panes.editor.asked == [PaneEdit(range: 34..<40, text: "pin")])
    #expect(panes.editor.carriedOut == [[PaneEdit(range: 34..<40, text: "pin")]])
    #expect(panes.result.documentView.string == "needle\nneedle\npre needle post\nend pin")
    #expect(panes.a.documentView.string == SearchPanes.aText)
    #expect(panes.base.documentView.string == SearchPanes.baseText)
    #expect(panes.observer.replacements == ["will 0", "did one 1"])
    #expect(panes.editor.undoManager?.undoActionName == "Replace")
  }

  @Test func replacementThatTheDelegateRefusesLeavesTheTextAlone() throws {
    let panes = SearchPanes()
    defer { panes.window.close() }
    panes.search.scope = .pane(panes.result)
    panes.editor.answer = { _ in [] }
    let first = try #require(panes.occurrences(of: "needle").first)
    #expect(panes.search.shouldReplaceCharacters(inRanges: [NSValue(range: first)], with: ["x"]))
    panes.search.replaceCharacters(in: first, with: "x")
    panes.search.didReplaceCharacters()
    #expect(panes.editor.asked == [PaneEdit(range: 0..<6, text: "x")])
    #expect(panes.editor.carriedOut.isEmpty)
    #expect(panes.result.documentView.string == SearchPanes.resultText)
  }

  @Test func replaceAllIsOneStepOfUndoNamedAfterIt() throws {
    let panes = SearchPanes()
    defer { panes.window.close() }
    let undoManager = try #require(panes.editor.undoManager)
    // Every report makes a group of its own, so only the search can join them into one step.
    undoManager.groupsByEvent = false
    panes.search.scope = .pane(panes.result)
    let ranges = panes.occurrences(of: "needle")
    #expect(
      panes.search.shouldReplaceCharacters(
        inRanges: ranges.map { NSValue(range: $0) }, with: ranges.map { _ in "pin" }))
    // The finder replaces from the last match to the first, in the text it began with.
    for range in ranges.reversed() {
      panes.search.replaceCharacters(in: range, with: "pin")
    }
    panes.search.didReplaceCharacters()
    #expect(panes.result.documentView.string == "pin\nneedle\npre needle post\nend pin")
    #expect(panes.editor.carriedOut.count == 2)
    #expect(panes.observer.replacements == ["will 0", "did all 2"])
    #expect(undoManager.undoActionName == "Replace All")
    #expect(undoManager.undoActionName == PaneSearch.undoActionName(replacingAll: true))
    undoManager.undo()
    #expect(panes.result.documentView.string == SearchPanes.resultText)
    #expect(!undoManager.canUndo)
  }

  @Test func selectionStartsInThePaneWithTheFocusAtTheNextPieceThatIsSearched() {
    let panes = SearchPanes()
    defer { panes.window.close() }
    panes.window.makeFirstResponder(panes.a.documentView)
    // The filler row between the second and the fourth row of A.
    panes.a.documentView.setSelectedRange(NSRange(location: 20, length: 0))
    // A's lines take 0..<19, the base and the result 20..<26 and 27..<33, with a line feed
    // after each; the fourth row of A starts at 34.
    #expect(panes.search.firstSelectedRange == NSRange(location: 34, length: 0))
    // A selection that reaches beyond the first two rows of A ends with them.
    panes.a.documentView.setSelectedRange(NSRange(location: 8, length: 30))
    #expect(panes.search.firstSelectedRange == NSRange(location: 8, length: 11))
  }

  @Test func selectingAMatchOutsideAFindCommandLeavesTheFocusWhereTheUserPutIt() {
    let panes = SearchPanes()
    defer { panes.window.close() }
    // The finder selects its current match as the find bar loses the focus to a click in A.
    panes.window.makeFirstResponder(panes.a.documentView)
    panes.search.selectedRanges = [NSValue(range: NSRange(location: 46, length: 6))]
    #expect(panes.base.documentView.selectedRange() == NSRange(location: 21, length: 6))
    #expect(panes.window.firstResponder === panes.a.documentView)
  }

  @Test func selectingAMatchLeavesTheFocusWhereItIsOutsideThePanes() {
    let panes = SearchPanes()
    defer { panes.window.close() }
    panes.window.makeFirstResponder(nil)
    panes.search.selectedRanges = [NSValue(range: NSRange(location: 46, length: 6))]
    #expect(panes.base.documentView.selectedRange() == NSRange(location: 21, length: 6))
    #expect(panes.window.firstResponder === panes.window)
  }

  @Test func revealedMatchIsSelectedInItsPaneAsTheMarkOfTheCurrentMatch() throws {
    let panes = SearchPanes()
    defer { panes.window.close() }
    let matches = panes.occurrences(of: "needle")
    panes.search.scrollRangeToVisible(matches[4])
    #expect(panes.a.documentView.selectedRange() == NSRange(location: 21, length: 6))
    panes.search.scrollRangeToVisible(matches[5])
    #expect(panes.base.documentView.selectedRange() == NSRange(location: 21, length: 6))
    // Find Next goes on from the pane of the last match while the focus is elsewhere.
    #expect(panes.search.firstSelectedRange == matches[5])
  }

  @Test func eachPaneShowsItsOwnStretchOfTheSearchText() {
    let panes = SearchPanes()
    defer { panes.window.close() }
    var range = NSRange()
    #expect(
      panes.search.contentView(at: 15, effectiveCharacterRange: &range) === panes.a.documentView)
    #expect(range == NSRange(location: 0, length: 19))
    // The line feed between two lines of A counts with A.
    #expect(
      panes.search.contentView(at: 12, effectiveCharacterRange: &range) === panes.a.documentView)
    #expect(
      panes.search.contentView(at: 47, effectiveCharacterRange: &range)
        === panes.base.documentView)
    #expect(range == NSRange(location: 46, length: 6))
    // The line feed between A and the base counts with the base.
    #expect(
      panes.search.contentView(at: 45, effectiveCharacterRange: &range)
        === panes.base.documentView)
    #expect(
      panes.search.contentView(at: 55, effectiveCharacterRange: &range)
        === panes.result.documentView)
    #expect(range == NSRange(location: 53, length: 21))
  }

  @Test func findIndicatorStandsOnTheRowOfTheMatch() throws {
    let panes = SearchPanes()
    defer { panes.window.close() }
    let rects = try #require(
      panes.search.rects(forCharacterRange: NSRange(location: 46, length: 6)))
    try #require(rects.count == 1, "\(rects)")
    let rect = rects[0].rectValue
    let row = panes.base.verticalSpan(ofRows: 2..<3)
    #expect(rect.minY == row.lowerBound)
    #expect(rect.height == row.upperBound - row.lowerBound)
    let width = ("needle" as NSString).size(withAttributes: [.font: panes.base.theme.font]).width
    #expect(abs(rect.width - width) < 0.5)
  }

  @Test func visibleTextIsReportedForEveryPane() {
    let panes = SearchPanes()
    defer { panes.window.close() }
    let visible = panes.search.visibleCharacterRanges.map(\.rangeValue)
    // Every pane shows all of its text, which is all but the six line feeds between pieces.
    #expect(visible.map(\.length).reduce(0, +) == (panes.search.string as NSString).length - 6)
  }

  @Test func findCommandsOfAPaneAmongTheSectionsAreValidatedByTheSearch() {
    let panes = SearchPanes()
    defer { panes.window.close() }
    let replaceAll = NSMenuItem(
      title: "Replace All", action: #selector(NSTextView.performTextFinderAction(_:)),
      keyEquivalent: "")
    replaceAll.tag = NSTextFinder.Action.replaceAll.rawValue
    // The result is editable, but the search goes through all panes, where nothing is replaced.
    #expect(!panes.result.documentView.validateMenuItem(replaceAll))
    #expect(
      panes.search.validate(replaceAll) == panes.result.documentView.validateMenuItem(replaceAll))
  }

  @Test func searchingNeverSwitchesAPaneToTheOlderTextSystem() throws {
    let panes = SearchPanes()
    defer { panes.window.close() }
    var switches = 0
    let observers = [panes.a, panes.base, panes.result].map { pane in
      NotificationCenter.default.addObserver(
        forName: NSTextView.willSwitchToNSLayoutManagerNotification, object: pane.documentView,
        queue: nil
      ) { _ in MainActor.assumeIsolated { switches += 1 } }
    }
    defer { observers.forEach(NotificationCenter.default.removeObserver) }
    panes.search.scope = .pane(panes.result)
    let ranges = panes.occurrences(of: "needle")
    for range in ranges {
      panes.search.scrollRangeToVisible(range)
      _ = panes.search.rects(forCharacterRange: range)
      var stretch = NSRange()
      let view = panes.search.contentView(at: range.location, effectiveCharacterRange: &stretch)
      try drawCharacters(of: range, in: view, panes: panes)
    }
    _ = panes.search.visibleCharacterRanges
    #expect(
      panes.search.shouldReplaceCharacters(
        inRanges: ranges.map { NSValue(range: $0) }, with: ranges.map { _ in "pin" }))
    for range in ranges.reversed() {
      panes.search.replaceCharacters(in: range, with: "pin")
    }
    panes.search.didReplaceCharacters()
    #expect(switches == 0)
    for pane in [panes.a, panes.base, panes.result] {
      #expect(pane.documentView.textLayoutManager != nil)
    }
  }

  @Test func findIndicatorDrawsTheCharactersOfTheMatchInBlack() throws {
    let panes = SearchPanes()
    defer { panes.window.close() }
    let range = NSRange(location: 46, length: 6)
    let ink = try drawCharacters(of: range, in: panes.base.documentView, panes: panes)
    #expect(ink > 20)
  }

  /// Draws the characters of `range` of the search text as the find indicator does, into a
  /// bitmap of `view`, and returns the number of dark pixels within the rectangles of the range.
  @discardableResult
  private func drawCharacters(of range: NSRange, in view: NSView, panes: SearchPanes) throws
    -> Int
  {
    let bounds = view.bounds
    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    context.cgContext.translateBy(x: 0, y: bounds.height)
    context.cgContext.scaleBy(x: 1, y: -1)
    NSColor.white.setFill()
    bounds.fill()
    panes.search.drawCharacters(in: range, forContentView: view)
    NSGraphicsContext.restoreGraphicsState()
    let rects = panes.search.rects(forCharacterRange: range)?.map(\.rectValue) ?? []
    var ink = 0
    for rect in rects {
      for y in Int(rect.minY)..<Int(rect.maxY) {
        for x in Int(rect.minX)..<Int(rect.maxX) {
          if let color = bitmap.colorAt(x: x, y: y), color.brightnessComponent < 0.5 {
            ink += 1
          }
        }
      }
    }
    return ink
  }
}
