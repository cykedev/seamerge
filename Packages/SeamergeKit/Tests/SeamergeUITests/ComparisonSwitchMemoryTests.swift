import AppKit
import Darwin
import MergeModel
import Testing

@testable import SeamergeUI

/// Switching the comparison mode again and again: each switch is a step of undo that keeps the
/// comparison it replaced, which must not keep a copy of the texts of the files.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct ComparisonSwitchMemoryTests {
  /// The lines of each file, long enough that a copy of the texts stands out from the noise of
  /// the process; every 40th line differs only in the amount of whitespace.
  private static let lineCount = 4_000

  @Test func switchingBackAndForthKeepsNoCopyOfTheTextsPerStepOfUndo() async throws {
    let old = (0..<Self.lineCount).map { line in
      "let value\(line) = [" + (0..<40).map { "\"item\($0)\"" }.joined(separator: ", ") + "]"
    }
    var new = old
    for line in stride(from: 20, to: Self.lineCount, by: 40) {
      new[line] = new[line].replacing(" = ", with: "  =  ")
    }
    let oldText = Data(old.joined(separator: "\n").utf8)
    let session = try await Session.diff(
      old: SourceFile(bytes: oldText, label: "old.txt"),
      new: SourceFile(bytes: Data(new.joined(separator: "\n").utf8), label: "new.txt"),
      mode: .windowDefault)
    // Without events to group them, the steps of undo are grouped by hand.
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let controller = try Windows.controller(for: session, undoManager: undoManager)
    let window = try #require(controller.window)
    defer { window.close() }
    func switchThereAndBack() async {
      for mode in [ComparisonMode.exact, .windowDefault] {
        undoManager.beginUndoGrouping()
        await controller.switchComparison(to: ComparisonOptions(mode: mode))
        undoManager.endUndoGrouping()
        window.contentView?.layoutSubtreeIfNeeded()
      }
    }

    // The first switches make what every later one reuses.
    await switchThereAndBack()
    let before = Self.bytesInUse()
    for _ in 0..<4 {
      await switchThereAndBack()
    }
    let growth = Double(Self.bytesInUse() - before) / 1_048_576

    #expect(controller.comparisonOptions.mode == .windowDefault)
    // Eight more steps of undo, each with a copy of both texts, would take 16 times the size of
    // a file; the positions of their rows take a fraction of one.
    let fileSize = Double(oldText.count) / 1_048_576
    #expect(growth < fileSize, "\(growth) MB more after 8 switches of files of \(fileSize) MB")
  }

  /// The bytes that the process has allocated and not freed.
  ///
  /// Unlike its footprint, it leaves out the pages that freed memory leaves between allocations,
  /// which grow and shrink with the order of the allocations rather than with what is kept.
  private static func bytesInUse() -> Int {
    var statistics = malloc_statistics_t()
    malloc_zone_statistics(nil, &statistics)
    return statistics.size_in_use
  }
}
