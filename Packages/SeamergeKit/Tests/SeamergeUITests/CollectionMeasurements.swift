import AppKit
import Foundation
import GitSupport
import Testing

@testable import SeamergeUI

/// Measures how long the main actor is held at a stretch while a window that compares several
/// large files opens, and while it goes to another one, each until the window shows the lines of
/// the file, and how long it then takes to draw them.
///
/// The measurement runs only on demand, never in the check of the repository: the environment
/// variable `SEAMERGE_MEASURE_COLLECTION` names the case of ``LargeFileCase``, whose files the
/// collection holds three times under other paths. The values go to the standard output.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(30)))
struct CollectionMeasurements {
  nonisolated static var chosenCase: String? {
    ProcessInfo.processInfo.environment["SEAMERGE_MEASURE_COLLECTION"]
  }

  @Test(.enabled(if: chosenCase != nil))
  func measureOpeningAndGoingToAnotherFile() async throws {
    let name = try #require(Self.chosenCase)
    let largeCase = try #require(LargeFileCase.all.first { $0.name == name }, "No case \(name)")
    #expect(!largeCase.isMerge, "A collection compares files")
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "SeamergeCollectionMeasurements-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: folder) }
    let files = try LargeFileRun.writeFiles(of: largeCase, into: folder)
    let collected = (1...3).map { number in
      let path = "Sources/File\(number).\(largeCase.fileExtension)"
      return CollectedFile(
        old: SessionFile(url: files.a, label: path), new: SessionFile(url: files.b, label: path),
        difftool: DifftoolContext(
          path: path, filePosition: FilePosition(number: number, count: 3)))
    }
    try await Self.openAndCloseASmallWindow()

    let clock = ContinuousClock()
    var controller: SessionWindowController?
    var openingTime = Duration.zero
    let openingHold = try await LargeFileRun.longestHold {
      let start = clock.now
      let opened = try await SessionWindowController(
        collection: FileCollection(files: collected), undoManager: UndoManager(),
        settings: .private())
      controller = opened
      await opened.comparisonFill?.value
      await opened.fileLoad?.value
      openingTime = clock.now - start
    }
    let opened = try #require(controller)
    defer { opened.window?.close() }
    let openingDrawing = clock.measure { Self.draw(opened) }
    #expect(opened.layout.sourcePane(.b)?.documentView.string.isEmpty == false)

    var switchTime = Duration.zero
    let switchHold = await LargeFileRun.longestHold {
      let start = clock.now
      // Not the file after the first, which the window reads ahead.
      opened.showFile(at: 2)
      await opened.fileLoad?.value
      switchTime = clock.now - start
    }
    let switchDrawing = clock.measure { Self.draw(opened) }
    #expect(opened.window?.title == collected[2].path)

    print("MEASURE \(name) open-longest-hold \(Self.milliseconds(openingHold))")
    print("MEASURE \(name) open-total \(Self.milliseconds(openingTime))")
    print("MEASURE \(name) open-draw \(Self.milliseconds(openingDrawing))")
    print("MEASURE \(name) other-file-longest-hold \(Self.milliseconds(switchHold))")
    print("MEASURE \(name) other-file-total \(Self.milliseconds(switchTime))")
    print("MEASURE \(name) other-file-draw \(Self.milliseconds(switchDrawing))")
  }

  /// Lays out and draws the window as it would show.
  private static func draw(_ controller: SessionWindowController) {
    guard let contentView = controller.window?.contentView else { return }
    contentView.layoutSubtreeIfNeeded()
    guard let picture = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)
    else { return }
    contentView.cacheDisplay(in: contentView.bounds, to: picture)
  }

  /// Opens a small comparison and draws it once, so that what the first window of a process
  /// costs once does not count against the large one.
  private static func openAndCloseASmallWindow() async throws {
    let controller = try Windows.controller(
      for: try await SampleDiffs.diff(old: "a\nb\n", new: "a\nc\n"))
    draw(controller)
    controller.window?.close()
  }

  private static func milliseconds(_ duration: Duration) -> Int {
    Int(duration / .milliseconds(1))
  }
}
