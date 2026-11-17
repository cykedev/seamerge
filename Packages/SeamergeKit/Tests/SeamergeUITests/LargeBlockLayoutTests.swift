import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Checks that jumping, showing all lines and switching the arrangement in a comparison of few
/// large blocks lay out the text in view, not the text above it: the paragraphs that TextKit
/// makes for each step do not grow with the length of the file.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct LargeBlockLayoutTests {
  /// The steps, each from where the one before left the window.
  private static let steps: [(name: String, command: SessionCommand)] = [
    ("Last Change", .lastChange), ("Show All Lines", .showAllLines),
    ("Collapse Unchanged Lines", .collapseUnchangedLines), ("Show All Lines", .showAllLines),
    ("Connected Sides", .showConnectedSides), ("Single Column", .showSingleColumn),
    ("Aligned Lines", .showAlignedLines),
  ]

  @Test func stepsLayOutAsMuchTextInAFileFourTimesAsLong() async throws {
    let short = try await paragraphsMade(lineCount: 5_000)
    let long = try await paragraphsMade(lineCount: 20_000)
    for (index, step) in Self.steps.enumerated() {
      // Laying out everything above the view would take four times as many in the long file.
      #expect(
        long[index] <= 2 * max(short[index], 50),
        "\(step.name): \(short[index]) paragraphs, then \(long[index])")
    }
  }

  /// The paragraphs that TextKit makes in all panes for each of the steps, in a comparison of
  /// `lineCount` lines with five large changes.
  private func paragraphsMade(lineCount: Int) async throws -> [Int] {
    let largeCase = LargeFileCase(name: "large", lineCount: lineCount, kind: .fewLargeChanges)
    let texts = largeCase.texts()
    let session = try await Session.diff(
      old: SourceFile(bytes: Data(texts.a.utf8), label: "old.swift"),
      new: SourceFile(bytes: Data(texts.b.utf8), label: "new.swift"), mode: .windowDefault)
    let controller = try Windows.controller(for: session)
    let window = try #require(controller.window)
    defer { window.close() }
    var made: [Int] = []
    for step in Self.steps {
      let counters = Windows.panes(of: controller).compactMap(ParagraphCounter.attach(to:))
      controller.perform(step.command)
      window.contentView?.layoutSubtreeIfNeeded()
      made.append(counters.reduce(0) { $0 + $1.count })
      for counter in counters {
        counter.detach()
      }
    }
    return made
  }
}

/// Counts the paragraphs that the content storage of a pane makes, standing in for its delegate
/// and passing on to it what the pane answers: how to make a paragraph and which to leave out.
@MainActor
private final class ParagraphCounter: NSObject, @MainActor NSTextContentStorageDelegate {
  private let storage: NSTextContentStorage
  private let delegate: (any NSTextContentStorageDelegate)?

  /// The number of paragraphs made since the counter was attached.
  private(set) var count = 0

  private init(storage: NSTextContentStorage) {
    self.storage = storage
    delegate = storage.delegate
    super.init()
  }

  /// A counter of the paragraphs of the text of `pane`, attached until it is detached.
  static func attach(to pane: PaneView) -> ParagraphCounter? {
    guard let storage = pane.documentView.textContentStorage else { return nil }
    let counter = ParagraphCounter(storage: storage)
    storage.delegate = counter
    return counter
  }

  /// Gives the content storage its delegate back.
  func detach() {
    storage.delegate = delegate
  }

  func textContentStorage(
    _ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange
  ) -> NSTextParagraph? {
    count += 1
    return delegate?.textContentStorage?(textContentStorage, textParagraphWith: range)
  }

  func textContentManager(
    _ textContentManager: NSTextContentManager, shouldEnumerate textElement: NSTextElement,
    options: NSTextContentManager.EnumerationOptions
  ) -> Bool {
    delegate?.textContentManager?(
      textContentManager, shouldEnumerate: textElement, options: options) ?? true
  }
}
