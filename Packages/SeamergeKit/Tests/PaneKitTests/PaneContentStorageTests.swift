import AppKit
import Testing

@testable import PaneKit

/// Checks that the content storage of a pane, which steps over hidden ranges in one go,
/// enumerates exactly the paragraphs, in the order and with the result, that TextKit's own
/// storage does when its delegate leaves out each hidden paragraph.
@MainActor
@Suite struct PaneContentStorageTests {
  /// Leaves out the paragraphs that start within one of the hidden ranges.
  private final class Hider: NSObject, NSTextContentStorageDelegate {
    var hiddenRanges: [Range<Int>] = []

    func textContentManager(
      _ textContentManager: NSTextContentManager, shouldEnumerate textElement: NSTextElement,
      options: NSTextContentManager.EnumerationOptions
    ) -> Bool {
      guard let range = textElement.elementRange else { return true }
      let start = textContentManager.offset(
        from: textContentManager.documentRange.location, to: range.location)
      return !hiddenRanges.contains { $0.contains(start) }
    }
  }

  /// One enumeration: the starts of the paragraphs it visited and the offset it returned.
  private struct Enumeration: Equatable {
    var starts: [Int]
    var result: Int?
  }

  private func enumerate(
    _ storage: NSTextContentStorage, from offset: Int?, reverse: Bool, stopAfter count: Int?
  ) -> Enumeration {
    let documentStart = storage.documentRange.location
    let location = offset.flatMap { storage.location(documentStart, offsetBy: $0) }
    var starts: [Int] = []
    let result = storage.enumerateTextElements(
      from: location, options: reverse ? .reverse : []
    ) { element in
      starts.append(
        element.elementRange.map { storage.offset(from: documentStart, to: $0.location) } ?? -1)
      return count.map { starts.count < $0 } ?? true
    }
    return Enumeration(
      starts: starts, result: result.map { storage.offset(from: documentStart, to: $0) })
  }

  /// A storage of `text` with a layout manager, as TextKit enumerates only then.
  private func storage(_ storage: NSTextContentStorage, text: String) -> NSTextContentStorage {
    storage.textStorage = NSTextStorage(string: text)
    storage.addTextLayoutManager(NSTextLayoutManager())
    return storage
  }

  @Test func enumerationStepsOverHiddenRangesAsTheDelegateLeavesOutTheirParagraphs() {
    // Paragraphs start at 0, 3, 6, 9 and 12; the ranges hide those at 3 and 6, and the last.
    let text = "aa\nbb\ncc\ndd\nee"
    let hiddenRanges = [3..<9, 12..<14]
    let paneStorage = PaneContentStorage()
    paneStorage.hiddenRanges = hiddenRanges
    let pane = storage(paneStorage, text: text)

    #expect(enumerate(pane, from: 0, reverse: false, stopAfter: nil).starts == [0, 9])
    #expect(enumerate(pane, from: 4, reverse: false, stopAfter: nil).starts == [9])
    #expect(enumerate(pane, from: 14, reverse: true, stopAfter: nil).starts == [9, 0])
    #expect(enumerate(pane, from: 9, reverse: true, stopAfter: nil).starts == [0])
    #expect(enumerate(pane, from: 0, reverse: false, stopAfter: 1).result == 3)
  }

  /// Random texts with random hidden ranges, enumerated from random places both ways and stopped
  /// at random, from the fixed seed 1613.
  @Test func randomEnumerationsVisitTheParagraphsThatTheDelegateShows() {
    var generator = SplitMix64(seed: 1613)
    for _ in 0..<300 {
      let lineCount = Int.random(in: 1...40, using: &generator)
      var text = ""
      var paragraphStarts: [Int] = []
      for _ in 0..<lineCount {
        paragraphStarts.append(text.utf16.count)
        text += String(repeating: "x", count: Int.random(in: 0...3, using: &generator))
        // A lone carriage return starts a paragraph for TextKit within the row.
        if Int.random(in: 0..<8, using: &generator) == 0 {
          text += "\ry"
        }
        text += Int.random(in: 0..<6, using: &generator) == 0 ? "\r\n" : "\n"
      }
      if Bool.random(using: &generator) {
        text += "tail"
        paragraphStarts.append(text.utf16.count - 4)
      }
      let length = text.utf16.count
      let bounds = paragraphStarts + [length]
      var hiddenRanges: [Range<Int>] = []
      var index = Int.random(in: 0..<bounds.count, using: &generator)
      while index < bounds.count - 1 {
        let end = Int.random(in: index + 1..<bounds.count, using: &generator)
        hiddenRanges.append(bounds[index]..<bounds[end])
        index = end + 1 + Int.random(in: 0...4, using: &generator)
      }

      let paneStorage = PaneContentStorage()
      paneStorage.hiddenRanges = hiddenRanges
      let hider = Hider()
      hider.hiddenRanges = hiddenRanges
      let plainStorage = NSTextContentStorage()
      plainStorage.delegate = hider
      let pane = storage(paneStorage, text: text)
      let plain = storage(plainStorage, text: text)
      for _ in 0..<20 {
        let offset: Int? =
          Int.random(in: 0..<10, using: &generator) == 0
          ? nil : Int.random(in: 0...length, using: &generator)
        let reverse = Bool.random(using: &generator)
        let stopAfter: Int? =
          Bool.random(using: &generator) ? Int.random(in: 1...6, using: &generator) : nil
        #expect(
          enumerate(pane, from: offset, reverse: reverse, stopAfter: stopAfter)
            == enumerate(plain, from: offset, reverse: reverse, stopAfter: stopAfter),
          "\(text.debugDescription), hidden \(hiddenRanges), from \(String(describing: offset))")
      }
    }
  }

  /// The text of the rows that `runs` hide behind their first rows, from the lines of the text.
  private func hiddenText(of lines: [String], behind runs: [CollapsedRun]) -> [Range<Int>] {
    var rowStarts = [0]
    for line in lines {
      rowStarts.append(rowStarts[rowStarts.count - 1] + line.utf16.count + 1)
    }
    let length = rowStarts[rowStarts.count - 1] - 1
    return runs.map { run in
      rowStarts[
        run.rows.lowerBound + 1]..<(run.rows.upperBound < lines.count
        ? rowStarts[run.rows.upperBound] : length)
    }
  }

  @Test func paneTellsItsStorageTheHiddenTextAfterCollapsingExpandingAndEditing() {
    var lines = (0..<120).map { "line \($0)" }
    let (pane, window, recorder) = EditingTests.editablePane(text: lines.joined(separator: "\n"))
    defer { window.close() }
    let storage = pane.textView.contentStorage
    #expect(storage.hiddenRanges.isEmpty)

    let runs = [CollapsedRun(rows: 10..<30), CollapsedRun(rows: 100..<120)]
    pane.setContent(pane.content, collapsedRuns: runs)
    #expect(storage.hiddenRanges == hiddenText(of: lines, behind: runs))

    pane.collapsedRuns = [runs[0], CollapsedRun(rows: 40..<60), runs[1]]
    #expect(storage.hiddenRanges == hiddenText(of: lines, behind: pane.collapsedRuns))

    pane.collapsedRuns = [runs[1]]
    #expect(storage.hiddenRanges == hiddenText(of: lines, behind: [runs[1]]))

    pane.textView.setSelectedRange(NSRange(location: 0, length: 0))
    pane.textView.insertText("typed ", replacementRange: NSRange(location: NSNotFound, length: 0))
    lines[0] = "typed " + lines[0]
    #expect(recorder.carriedOut.count == 1)
    #expect(storage.hiddenRanges == hiddenText(of: lines, behind: [runs[1]]))
  }
}
