import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// A merge of three files in a temporary folder with three conflicts, in a window that keeps its
/// work in a folder of work, and what the window reports as it ends.
@MainActor
final class WorkingMerge {
  static let base = "one\nbase 1\ntwo\nbase 2\nthree\nbase 3\nfour\n"
  static let a = "one\nA 1\ntwo\nA 2\nthree\nA 3\nfour\n"
  static let b = "one\nB 1\ntwo\nB 2\nthree\nB 3\nfour\n"

  let folder: URL
  let work: WorkFolder
  let prompts = PromptRecorder()
  let undoManager = UndoManager()
  let controller: SessionWindowController

  /// The files of the merge as the window read them.
  let inputs: Session.Inputs<SourceFile>

  /// How the window ended, once it reported it.
  private(set) var outcomes: [SessionOutcome] = []

  /// Whether the folder of work held the work of the merge each time the window reported its
  /// end.
  private(set) var heldWorkAtTheEnd: [Bool] = []

  private var endWaiter: CheckedContinuation<Void, Never>?

  /// A merge of the files in `folder`, or in a new folder with the texts above, whose result goes
  /// to `result.txt` for `waitingCaller`, or to no file for `nil`, as one from Compare Files; it
  /// keeps its work in `work`.
  init(
    in folder: URL? = nil, work: WorkFolder = WorkFolder(),
    waitingCaller: WaitingCaller? = .git
  ) async throws {
    let folder =
      folder
      ?? FileManager.default.temporaryDirectory.appending(
        path: "WorkingMerge-\(UUID().uuidString)", directoryHint: .isDirectory)
    self.folder = folder
    self.work = work
    try Self.writeFiles(into: folder)
    let session = try await Session.loadMerge(
      base: Self.file("base.txt", in: folder), a: Self.file("a.txt", in: folder),
      b: Self.file("b.txt", in: folder), mode: .windowDefault)
    inputs = session.inputs
    let resultURL = waitingCaller == nil ? nil : folder.appending(path: "result.txt")
    if let resultURL, !FileManager.default.fileExists(atPath: resultURL.path) {
      try Data("<<<<<<< conflict\n".utf8).write(to: resultURL)
    }
    controller = try Windows.controller(
      for: session, context: SessionContext(resultURL: resultURL, waitingCaller: waitingCaller),
      prompts: prompts, undoManager: undoManager, workKeeper: work.keeper())
    let workFile = work.url.appending(path: "\(MergeKey(session.inputs).rawValue).json")
    controller.onFinish = { [weak self] outcome in
      guard let self else { return }
      outcomes.append(outcome)
      heldWorkAtTheEnd.append(FileManager.default.fileExists(atPath: workFile.path))
      endWaiter?.resume()
      endWaiter = nil
    }
  }

  isolated deinit {
    // A test closes the window itself and waits for its end, so that nothing is written once
    // the folders are gone.
    if !controller.hasFinished {
      Issue.record("The window of the merge is still open")
    }
    do {
      if FileManager.default.fileExists(atPath: folder.path) {
        try FileManager.default.removeItem(at: folder)
      }
    } catch {
      Issue.record("Could not remove \(folder.path): \(error)")
    }
  }

  /// Writes the three files into `folder`, unless they are there already.
  static func writeFiles(into folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (name, text) in [("base.txt", base), ("a.txt", a), ("b.txt", b)] {
      let url = folder.appending(path: name)
      if !FileManager.default.fileExists(atPath: url.path) {
        try Data(text.utf8).write(to: url)
      }
    }
  }

  /// The file `name` in `folder`, labelled with its name.
  static func file(_ name: String, in folder: URL) -> SessionFile {
    SessionFile(url: folder.appending(path: name), label: name)
  }

  /// The blocks of the conflicts, in order.
  var conflicts: [Int] {
    controller.presentation.changes.blocks.indices.filter {
      controller.presentation.changes.blocks[$0].kind == .conflict
    }
  }

  /// Makes conflict `number`, counted from 0, the current block and takes `command` for it, as
  /// the user does.
  func decide(_ number: Int, _ command: SessionCommand) {
    controller.presentation.setCurrentBlock(conflicts[number])
    controller.perform(command)
    controller.endEvent()
  }

  /// Fires the timer of the folder of work and waits until what it started is written.
  func keepOnTime() async {
    work.timer.fire()
    await controller.workKeeper?.lastOperation?.value
  }

  /// The work the folder holds for the merge, if any.
  var keptWork: MergeWork? {
    get async throws { try await work.work(of: inputs) }
  }

  /// Closes the window, as its close button does once the window may close, and waits until it
  /// has reported how it ended.
  func close() async {
    controller.close()
    await ended()
  }

  /// Waits until the window has reported how it ended.
  func ended() async {
    if outcomes.isEmpty {
      await withCheckedContinuation { endWaiter = $0 }
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
}
