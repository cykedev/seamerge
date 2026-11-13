import AppKit
import GitSupport
import MergeModel
import SeamergeUI
import SessionIPC
import os

/// Learns when session windows open and close.
@MainActor
protocol SessionCoordinatorDelegate: AnyObject {
  /// A session window opened or closed; ``SessionCoordinator/windowControllers`` holds the open
  /// ones.
  func sessionCoordinatorDidChangeWindows(_ coordinator: SessionCoordinator)
}

/// Opens a window for each session: those the helper hands over through the socket, and those
/// the window Compare Files puts together.
///
/// Every session, a merge or a comparison of two files, gets a window of its own with an undo
/// manager of its own, built in the comparison mode of the window. For the helper, the
/// coordinator answers `opened` once the window shows, and the outcome once it closes; if the
/// helper goes away first, it tells the window, which stays open.
@MainActor
final class SessionCoordinator {
  /// Learns when windows open and close; the coordinator does not retain it.
  weak var delegate: (any SessionCoordinatorDelegate)?

  /// The open session windows, oldest first.
  private(set) var windowControllers: [SessionWindowController] = []

  private let socketURL: URL
  private let presentError: (any Error) -> Void
  private var kinds: [ObjectIdentifier: Session.Kind] = [:]
  private var serverTask: Task<Void, Never>?
  private var isFinishing = false
  private var servingCount = 0
  private var idleWaiters: [CheckedContinuation<Void, Never>] = []

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "App")

  /// Creates a coordinator that listens for the helper at `socketURL` once it starts, and shows
  /// what keeps a session from opening with `presentError`.
  init(socketURL: URL, presentError: @escaping (any Error) -> Void) {
    self.socketURL = socketURL
    self.presentError = presentError
  }

  /// Listens for the helper.
  ///
  /// - Throws: The error of the socket, such as ``SessionError/socketInUse(path:)`` while
  ///   another copy of the app listens.
  func start() throws(SessionError) {
    let server = try SessionServer(socketURL: socketURL)
    // The task keeps the coordinator until it stops listening in finish().
    serverTask = Task {
      await server.run { connection in
        await self.serve(connection)
      }
    }
  }

  /// Asks for each session window whose merge has unsaved changes whether to save it, as
  /// closing it does, and closes it; tells whether every one closed, which stops at the first
  /// that the user keeps open.
  func closeUnsavedWindowsAskingFirst() async -> Bool {
    for controller in windowControllers where controller.hasUnsavedChanges {
      guard await controller.closeAskingFirst() else { return false }
    }
    return true
  }

  /// Closes every session window, which tells each waiting helper how its session ended: a merge
  /// whether it is saved, a comparison that it was cancelled, so that Git compares no further
  /// files either; then stops listening.
  func finish() async {
    isFinishing = true
    for controller in windowControllers {
      controller.closeAsTheAppQuits()
    }
    await waitUntilIdle()
    serverTask?.cancel()
    await serverTask?.value
    serverTask = nil
  }

  /// Waits until no helper is being served: every helper has had its answer or has gone away.
  func waitUntilIdle() async {
    if servingCount > 0 {
      await withCheckedContinuation { idleWaiters.append($0) }
    }
  }

  /// The kind of session that `window` shows, if it is a session window.
  func kind(of window: NSWindow) -> Session.Kind? {
    windowControllers.first { $0.window === window }.flatMap { kinds[ObjectIdentifier($0)] }
  }

  /// Opens a window for the files of `comparison` in their roles and returns once it shows: a
  /// merge with a base, a comparison without one.
  ///
  /// Such a session has no file to save to and no Git behind it. While the app quits, nothing
  /// opens.
  ///
  /// - Throws: Why the files cannot be opened.
  func open(_ comparison: FileComparison) async throws(SessionLoadingError) {
    let file = { (url: URL) in SessionFile(url: url, label: url.lastPathComponent) }
    let session =
      if let base = comparison.base {
        try await Session.loadMerge(
          base: file(base), a: file(comparison.left), b: file(comparison.right))
      } else {
        try await Session.loadDiff(old: file(comparison.left), new: file(comparison.right))
      }
    let controller = SessionWindowController(
      session: session, context: SessionContext(), undoManager: UndoManager())
    guard !isFinishing else { return }
    show(controller, kind: session.kind) { _ in }
  }

  /// Serves the request of one helper until its window closes or the helper goes away.
  private func serve(_ connection: SessionConnection) async {
    servingCount += 1
    defer {
      servingCount -= 1
      if servingCount == 0 {
        for waiter in idleWaiters {
          waiter.resume()
        }
        idleWaiters = []
      }
    }
    let controller: SessionWindowController
    do {
      controller = try await Self.makeWindow(for: connection.request)
    } catch {
      presentError(error)
      await send(.closed(.cancelled), on: connection)
      return
    }
    guard !isFinishing else {
      await send(.closed(.cancelled), on: connection)
      return
    }

    let (endings, ending) = AsyncStream.makeStream(of: SessionEnding.self)
    show(controller, kind: connection.request.kind) { outcome in
      ending.yield(.closed(outcome))
    }
    do {
      try await connection.send(.opened)
    } catch {
      Self.logger.notice("The helper went away before its window opened")
      controller.callerDisconnected()
      return
    }
    let disconnection = Task {
      await connection.waitUntilDisconnected()
      ending.yield(.disconnected)
    }
    defer { disconnection.cancel() }
    var iterator = endings.makeAsyncIterator()
    switch await iterator.next() {
    case .closed(let outcome):
      await send(.closed(SessionIPC.SessionOutcome(outcome)), on: connection)
    case .disconnected, nil:
      Self.logger.notice("The helper no longer waits for its window")
      controller.callerDisconnected()
    }
  }

  /// Shows `controller`, which shows a session of `kind`, and keeps it until its window closes;
  /// then `onFinish` learns how the session ended.
  private func show(
    _ controller: SessionWindowController, kind: Session.Kind,
    onFinish: @escaping (SeamergeUI.SessionOutcome) -> Void
  ) {
    controller.onFinish = { [weak self, weak controller] outcome in
      onFinish(outcome)
      guard let self, let controller else { return }
      windowControllers.removeAll { $0 === controller }
      kinds[ObjectIdentifier(controller)] = nil
      delegate?.sessionCoordinatorDidChangeWindows(self)
    }
    windowControllers.append(controller)
    kinds[ObjectIdentifier(controller)] = kind
    controller.showWindow(nil)
    delegate?.sessionCoordinatorDidChangeWindows(self)
  }

  private func send(_ event: SessionEvent, on connection: SessionConnection) async {
    do {
      try await connection.send(event)
    } catch {
      Self.logger.notice("The helper went away before the answer: \(String(describing: error))")
    }
  }

  /// Reads the files of `request` and opens a window for their merge or comparison, in the
  /// comparison mode of the window.
  ///
  /// A merge knows who waits for it: Git where the command line says so, else the command line.
  /// Every side of a merge shows the name of the file it is merged into, since Git hands over
  /// temporary copies; so does every side of a comparison that Git started, unless the command
  /// line names it. A comparison whose files cannot be compared, such as of an image, still gets
  /// a window that says why, so that a run of `git difftool` goes on past it; the merge of a
  /// file that is not text gets a window that asks which side to take as a whole.
  ///
  /// - Throws: Why the files of a merge cannot be opened.
  private static func makeWindow(
    for request: SessionRequest
  ) async throws(SessionLoadingError) -> SessionWindowController {
    switch request {
    case .merge(let merge):
      let label = merge.output.lastPathComponent
      let (a, b) = (
        SessionFile(url: merge.remote, label: label), SessionFile(url: merge.local, label: label)
      )
      let context = SessionContext(
        resultURL: merge.output,
        git: GitContext(merge.context, hasCommonAncestor: merge.base != nil),
        waitingCaller: merge.isRunByGit ? .git : .commandLine)
      do {
        let session = try await Session.loadMerge(
          base: merge.base.map { SessionFile(url: $0, label: label) }, a: a, b: b)
        return SessionWindowController(
          session: session, context: context, undoManager: UndoManager())
      } catch .binaryFile {
        Self.logger.notice("Asking which side of the binary file to take")
        return try await SessionWindowController(
          binaryMerge: BinaryMerge(a: a, b: b, output: merge.output), context: context,
          undoManager: UndoManager())
      }
    case .diff(let diff):
      let file = { (url: URL, label: String?) in
        SessionFile(url: url, label: label ?? diff.displayPath ?? url.lastPathComponent)
      }
      let (old, new) = (file(diff.left, diff.leftLabel), file(diff.right, diff.rightLabel))
      let context = SessionContext(difftool: DifftoolContext(diff))
      do {
        let session = try await Session.loadDiff(old: old, new: new)
        return SessionWindowController(
          session: session, context: context, undoManager: UndoManager())
      } catch {
        Self.logger.notice("Showing why the files cannot be compared: \(String(describing: error))")
        return try await SessionWindowController(
          unavailable: UnavailableComparison(old: old, new: new, reason: error), context: context,
          undoManager: UndoManager())
      }
    }
  }
}

extension SessionRequest {
  /// Whether the request asks for a merge or a comparison.
  fileprivate var kind: Session.Kind {
    switch self {
    case .merge: .merge
    case .diff: .diff
    }
  }
}

/// How a session ended for the helper: its window closed, or the helper went away first.
private enum SessionEnding: Sendable {
  case closed(SeamergeUI.SessionOutcome)
  case disconnected
}

extension SessionIPC.SessionOutcome {
  /// The outcome the helper reports for a window that closed with `outcome`.
  init(_ outcome: SeamergeUI.SessionOutcome) {
    self =
      switch outcome {
      case .saved: .saved
      case .cancelled: .cancelled
      }
  }
}
