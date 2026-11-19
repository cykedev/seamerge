import MergeModel
import PaneKit
import Testing
import TextBasics

@testable import SeamergeUI

struct ResultTextTests {
  @Test func paneShowsALineFeedForEveryLineBreakAndNoneAtTheEnd() {
    let text = ResultText("a\r\nb\rc\u{2028}d\n")

    #expect(text.paneLength == 7)
    #expect(text.paneOffset(ofFileOffset: 3) == 2)
    #expect(text.fileOffset(ofPaneOffset: 2) == 3)
    // The end of the pane's text lies before the line break that ends the file.
    #expect(text.fileOffset(ofPaneOffset: 7) == 8)
    #expect(text.paneOffset(ofFileOffset: 9) == 7)
  }

  @Test func typedLineBreakTakesTheLineBreakOfItsLine() {
    let text = ResultText("one\r\ntwo\nthree")

    #expect(text.replacement(for: PaneEdit(range: 1..<1, text: "\n")).text == "\r\n")
    #expect(text.replacement(for: PaneEdit(range: 5..<5, text: "x\ny")).text == "x\ny")
    // The last line has no line break of its own and takes that of the line before.
    #expect(text.replacement(for: PaneEdit(range: 10..<10, text: "\n")).text == "\n")
    #expect(ResultText("one").replacement(for: PaneEdit(range: 3..<3, text: "\n")).text == "\n")
  }

  @Test func typingAtTheEndOfTheLastLineGoesBeforeTheFinalLineBreak() {
    var text = ResultText("one\r\n")
    let replacement = text.replacement(for: PaneEdit(range: 3..<3, text: "\n"))

    #expect(replacement == TextReplacement(range: 3..<3, text: "\r\n"))
    let (edit, replaced) = text.carryOut(replacement)
    #expect(edit == PaneEdit(range: 3..<3, text: "\n"))
    #expect(replaced.isEmpty)
    #expect(text.string == "one\r\n\r\n")
  }

  @Test func replacementOfTheEndCoversTheEndOfThePane() {
    var text = ResultText("one\ntwo\n")

    let (edit, replaced) = text.carryOut(TextReplacement(range: 4..<8, text: ""))

    #expect(replaced == "two\n")
    #expect(edit == PaneEdit(range: 3..<7, text: ""))
    #expect(text.string == "one\n")
  }

  @Test func insertionAfterTheFinalLineBreakShowsThatLineBreak() {
    var text = ResultText("one\n")

    let (edit, _) = text.carryOut(TextReplacement(range: 4..<4, text: "two\n"))

    #expect(edit == PaneEdit(range: 3..<3, text: "\ntwo"))
    #expect(text.string == "one\ntwo\n")
  }

  @Test func carriageReturnAndLineFeedThatMeetBecomeOneLineBreak() {
    var text = ResultText("a\rX\nb")

    let (edit, replaced) = text.carryOut(TextReplacement(range: 2..<3, text: ""))

    #expect(replaced == "X")
    #expect(edit == PaneEdit(range: 1..<4, text: "\n"))
    #expect(text.string == "a\r\nb")
    #expect(text.paneLength == 3)
  }

  @Test func rowsCountCharactersBeyondTheBasicPlaneAsTwoUnits() {
    let rows = ResultPaneContent.rows(of: "a😀\nb\r\nc")

    #expect(rows.text == "a😀\nb\nc")
    #expect(rows.starts == [0, 4, 6, 8])
    #expect(rows.lineEndings == [.lf, .crlf, nil])
    #expect(rows.row(ofPaneOffset: 5) == 1)
    // The file's text: "a😀\n" takes 0..<4, "b\r\n" 4..<7.
    #expect(rows.rows(ofUTF16: 4..<7) == 1..<2)
    #expect(rows.rows(ofUTF16: 7..<8) == 2..<3)
  }

  /// Random replacements, also of single units of a line break, keep the pane's form the
  /// visible form of the file, and the returned edits carry it from one to the next.
  @Test func randomReplacementsKeepBothFormsInStep() {
    let seed: UInt64 = 2026
    var generator = SeededGenerator(seed: seed)
    let pieces = [
      "a", "bc", "\n", "\r", "\r\n", "\u{2028}", "\u{85}", "é", "e", "\u{301}", "😀", "",
    ]
    for round in 0..<500 {
      var text = ResultText(
        (0..<Int.random(in: 0..<8, using: &generator)).map { _ in
          pieces.randomElement(using: &generator) ?? ""
        }.joined())
      var pane = ResultPaneContent.rows(of: text.string).text
      for step in 0..<12 {
        let units = Array(text.string.utf16)
        // Not between the units of a CRLF pair or of a surrogate pair.
        let offsets = (0...units.count).filter { offset in
          offset == 0 || offset == units.count
            || !(units[offset - 1] == 13 && units[offset] == 10)
              && !UTF16.isTrailSurrogate(units[offset])
        }
        let first = offsets.randomElement(using: &generator) ?? 0
        let second = offsets.randomElement(using: &generator) ?? 0
        let replacement = TextReplacement(
          range: min(first, second)..<max(first, second),
          text: (0..<Int.random(in: 0..<3, using: &generator)).map { _ in
            pieces.randomElement(using: &generator) ?? ""
          }.joined())
        let context = "seed \(seed), round \(round), step \(step): \(text.string.debugDescription)"
        let (edit, _) = text.carryOut(replacement)
        pane.replaceUTF16Range(edit.range, with: edit.text)
        let expected = Self.paneForm(of: text.string)
        #expect(pane == expected, "\(context)")
        #expect(text.paneLength == expected.utf16.count, "\(context)")
        #expect(text == ResultText(text.string), "\(context)")
        guard pane == expected else { return }
      }
    }
  }
}

extension ResultTextTests {
  /// `text` as the pane shows it, worked out on its own: a line feed for every line break, and
  /// none for the one that ends the text.
  static func paneForm(of text: String) -> String {
    var scalars: [Unicode.Scalar] = []
    var previous: Unicode.Scalar?
    for scalar in text.unicodeScalars {
      defer { previous = scalar }
      if scalar == "\n" && previous == "\r" {
        continue
      }
      scalars.append(["\r", "\u{85}", "\u{2028}", "\u{2029}"].contains(scalar) ? "\n" : scalar)
    }
    if scalars.last == "\n" {
      scalars.removeLast()
    }
    return String(String.UnicodeScalarView(scalars))
  }
}

/// A generator of random numbers that starts from a fixed seed, so that a random test can be
/// repeated: SplitMix64.
struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}

extension String {
  /// Replaces a UTF-16 range with `replacement`.
  mutating func replaceUTF16Range(_ range: Range<Int>, with replacement: String) {
    let start = utf16.index(startIndex, offsetBy: range.lowerBound)
    let end = utf16.index(start, offsetBy: range.count)
    replaceSubrange(start..<end, with: replacement)
  }
}
