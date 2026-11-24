import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// The merge of a ``WorkingMerge`` opened again as `git mergetool` opens it the next time: from
/// copies of its files in another folder under other names, in a window that looks for the work
/// kept for it.
@MainActor
final class RestoredMerge {
  let folder: URL
  let undoManager = UndoManager()
  let controller: SessionWindowController

  /// What VoiceOver heard from the window, in order.
  private(set) var announcements: [String] = []

  private var hasEnded = false
  private var endWaiter: CheckedContinuation<Void, Never>?

  /// Opens the files of `merge` from copies, with `changes` in place of the texts of their roles,
  /// as a merge that `waitingCaller` waits for, or none; the window shows once it is filled.
  init(
    copying merge: WorkingMerge, changing changes: [Role: String] = [:],
    waitingCaller: WaitingCaller? = .git
  ) async throws {
    folder = FileManager.default.temporaryDirectory.appending(
      path: "RestoredMerge-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var files: [Role: SessionFile] = [:]
    for (role, name) in [(Role.base, "base"), (.a, "a"), (.b, "b")] {
      let source = merge.folder.appending(path: "\(name).txt")
      let url = folder.appending(
        path: "result_\(name.uppercased())_\(UUID().uuidString.prefix(6)).txt")
      let bytes = try changes[role].map { Data($0.utf8) } ?? Data(contentsOf: source)
      try bytes.write(to: url)
      files[role] = SessionFile(url: url, label: "result.txt")
    }
    let resultURL = waitingCaller == nil ? nil : folder.appending(path: "result.txt")
    if let resultURL {
      try Data("<<<<<<< conflict\n".utf8).write(to: resultURL)
    }
    WindowAnimations.turnOff()
    TransparentWindows.turnOn()
    let base = try #require(files[.base])
    let a = try #require(files[.a])
    let b = try #require(files[.b])
    controller = try await SessionWindowController.openMerge(
      base: base, a: a, b: b, mode: .windowDefault,
      context: SessionContext(resultURL: resultURL, waitingCaller: waitingCaller),
      undoManager: undoManager, settings: .private(), workKeeper: merge.work.keeper())
    controller.presentation.announce = { [weak self] in self?.announcements.append($0) }
    controller.onFinish = { [weak self] _ in
      guard let self else { return }
      hasEnded = true
      endWaiter?.resume()
      endWaiter = nil
    }
    await controller.phase.filling?.value
    controller.showWindow(nil)
    controller.endEvent()
  }

  isolated deinit {
    if !hasEnded {
      Issue.record("The window of the restored merge is still open")
    }
    do {
      try FileManager.default.removeItem(at: folder)
    } catch {
      Issue.record("Could not remove \(folder.path): \(error)")
    }
  }

  /// The segment of each conflict as the result has it: its state and its text.
  var conflictSegments: [String] {
    get throws {
      let texts = try controller.segmentTexts
      let states = try controller.segmentStates
      let blocks = try controller.presentation.mergeResult.document.session.blocks
      return blocks.indices.filter { blocks[$0].kind == .conflict }.map {
        "\(states[$0]): \(texts[$0])"
      }
    }
  }

  /// Closes the window and waits until it has reported how it ended and kept its work.
  func close() async {
    controller.close()
    if !hasEnded {
      await withCheckedContinuation { endWaiter = $0 }
    }
  }
}
