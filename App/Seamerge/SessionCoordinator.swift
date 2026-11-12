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

/// Opens a window for each session that the helper hands over through the socket.
///
/// Every session gets a window of its own with an undo manager of its own, built in the
/// comparison mode of the window. The coordinator answers `opened` once the window shows.
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
    // The task keeps the coordinator until it stops listening in stop().
    serverTask = Task {
      await server.run { connection in
        await self.serve(connection)
      }
    }
  }

  /// Stops listening and lets every helper go.
  func stop() async {
    serverTask?.cancel()
    await serverTask?.value
    serverTask = nil
  }

  /// The kind of session that `window` shows, if it is a session window.
  func kind(of window: NSWindow) -> Session.Kind? {
    windowControllers.first { $0.window === window }.flatMap { kinds[ObjectIdentifier($0)] }
  }

  /// Serves the request of one helper until the helper goes away.
  private func serve(_ connection: SessionConnection) async {
    switch connection.request {
    case .merge(let merge):
      await serve(merge, on: connection)
    case .diff:
      Self.logger.notice("Refusing a comparison: the session window shows merges only")
      await send(.rejected(.unsupportedRequest), on: connection)
    }
  }

  private func serve(_ merge: SessionRequest.Merge, on connection: SessionConnection) async {
    let label = merge.output.lastPathComponent
    let controller: SessionWindowController
    do {
      controller = try await Self.makeWindow(
        base: merge.base.map { SessionFile(url: $0, label: label) },
        a: SessionFile(url: merge.remote, label: label),
        b: SessionFile(url: merge.local, label: label),
        context: SessionContext(
          resultURL: merge.output,
          git: GitContext(merge.context, hasCommonAncestor: merge.base != nil)))
    } catch {
      presentError(error)
      await send(.closed(.cancelled), on: connection)
      return
    }
    show(controller, kind: .merge)
    do {
      try await connection.send(.opened)
    } catch {
      Self.logger.notice("The helper went away before its window opened")
      return
    }
    await connection.waitUntilDisconnected()
  }

  /// Shows `controller`, which shows a session of `kind`, and keeps it until its window closes.
  private func show(_ controller: SessionWindowController, kind: Session.Kind) {
    controller.onFinish = { [weak self, weak controller] _ in
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

  /// Reads the files and opens a window for their merge, in the comparison mode of the window.
  private static func makeWindow(
    base: SessionFile?, a: SessionFile, b: SessionFile, context: SessionContext
  ) async throws(SessionLoadingError) -> SessionWindowController {
    let session = try await Session.loadMerge(base: base, a: a, b: b)
    return SessionWindowController(session: session, context: context, undoManager: UndoManager())
  }
}
