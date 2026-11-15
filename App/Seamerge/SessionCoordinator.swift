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
///
/// A comparison that comes with its origin joins the window of the other comparisons of that
/// origin while their collection receives files, or starts a collection with a window of its own.
/// The coordinator keeps a copy of each of its files and answers `accepted` at once, so that Git
/// goes on to the next file without waiting for the window. Once that window has closed, the
/// comparisons of the collection that still come are cancelled without a window. The two folders
/// of a directory diff become a collection of their own, whose window Git waits for.
///
/// While the app quits, the coordinator refuses every new session as `quitting`, so that the
/// helper opens the app again once this copy has gone, instead of ending without a window.
@MainActor
final class SessionCoordinator {
  /// Learns when windows open and close; the coordinator does not retain it.
  weak var delegate: (any SessionCoordinatorDelegate)?

  /// The open session windows, oldest first.
  private(set) var windowControllers: [SessionWindowController] = []

  private let socketURL: URL
  private let cache: CollectionCache
  private let settings: UserSettings
  private let presentError: (any Error) -> Void
  private var collections: [OpenCollection] = []
  private var kinds: [ObjectIdentifier: Session.Kind] = [:]
  private var serverTask: Task<Void, Never>?
  private var isFinishing = false
  private var servingCount = 0
  private var idleWaiters: [CheckedContinuation<Void, Never>] = []

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "App")

  /// Creates a coordinator that listens for the helper at `socketURL` once it starts, keeps the
  /// copies of the files of collections in `cache`, opens windows as `settings` say, and shows
  /// what keeps a session from opening with `presentError`.
  init(
    socketURL: URL, cache: CollectionCache = .standard, settings: UserSettings,
    presentError: @escaping (any Error) -> Void
  ) {
    self.socketURL = socketURL
    self.cache = cache
    self.settings = settings
    self.presentError = presentError
  }

  /// Listens for the helper.
  ///
  /// - Throws: The error of the socket, such as ``SessionError/socketInUse(path:)`` while
  ///   another copy of the app listens.
  func start() throws(SessionError) {
    let server = try SessionServer(socketURL: socketURL)
    // Only the copy of the app that listens owns the cache; copies left there are from a crash.
    cache.removeAll()
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
  ///
  /// Sessions that come meanwhile are refused as `quitting`, except further comparisons of a run
  /// whose window closed, which are cancelled with it.
  func finish() async {
    isFinishing = true
    for controller in windowControllers {
      controller.closeAsTheAppQuits()
    }
    await waitUntilIdle()
    serverTask?.cancel()
    await serverTask?.value
    serverTask = nil
    cache.removeAll()
  }

  /// Whether a helper is being served: it waits for a window or for its answer.
  var isServingHelper: Bool {
    servingCount > 0
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
  /// merge with a base, a comparison without one, or the files of two folders.
  ///
  /// Such a session has no file to save to and no Git behind it. While the app quits, nothing
  /// opens.
  ///
  /// - Throws: Why the files cannot be opened.
  func open(_ comparison: FileComparison) async throws(SessionLoadingError) {
    if let folders = comparison.folders {
      try await open(folders)
      return
    }
    let file = { (url: URL) in SessionFile(url: url, label: url.lastPathComponent) }
    let session =
      if let base = comparison.base {
        try await Session.loadMerge(
          base: file(base), a: file(comparison.left), b: file(comparison.right),
          mode: settings.comparisonMode)
      } else {
        try await Session.loadDiff(
          old: file(comparison.left), new: file(comparison.right), mode: settings.comparisonMode,
          ignoring: settings.ignoreRules)
      }
    let controller = SessionWindowController(
      session: session, context: SessionContext(), undoManager: UndoManager(), settings: settings)
    guard !isFinishing else { return }
    show(controller, kind: session.kind) { _ in }
  }

  /// Opens a window that compares the files of `folders` and returns once it shows, while the
  /// comparison goes on; the targets of links that it writes go when the window closes.
  ///
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if not even the window can be made.
  private func open(_ folders: FolderPair) async throws(SessionLoadingError) {
    let linkFolder = cache.makeFolder()
    let collection = FileCollection(comparing: folders, linkFolder: linkFolder)
    let end = { [cache] in
      collection.dismiss()
      cache.remove(linkFolder)
    }
    let controller: SessionWindowController
    do {
      controller = try await SessionWindowController(
        collection: collection, undoManager: UndoManager(), settings: settings)
    } catch {
      end()
      throw error
    }
    guard !isFinishing else {
      end()
      return
    }
    show(controller, kind: .diff) { _ in end() }
    collection.startComparing()
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
    switch connection.request {
    case .diff(let diff) where diff.origin != nil:
      await serveCollected(diff, on: connection)
      return
    case .folders(let folders):
      await serveFolders(folders, on: connection)
      return
    case .merge, .diff:
      break
    }
    guard !isFinishing else {
      await send(.rejected(.quitting), on: connection)
      return
    }
    let controller: SessionWindowController
    do {
      controller = try await Self.makeWindow(for: connection.request, settings: settings)
    } catch {
      presentError(error)
      await send(.closed(.cancelled), on: connection)
      return
    }
    guard !isFinishing else {
      await send(.rejected(.quitting), on: connection)
      return
    }

    await serveWindow(controller, kind: connection.request.kind, on: connection) {
      SessionIPC.SessionOutcome($0)
    }
  }

  /// Shows `controller` for the helper of `connection`, calls `afterShowing`, answers `opened`,
  /// and once the window closes, the outcome that `outcome` makes of how it closed; if the helper
  /// goes away first, tells the window.
  private func serveWindow(
    _ controller: SessionWindowController, kind: Session.Kind, on connection: SessionConnection,
    afterShowing: () -> Void = {},
    outcome: @escaping (SeamergeUI.SessionOutcome) -> SessionIPC.SessionOutcome
  ) async {
    let (endings, ending) = AsyncStream.makeStream(of: SessionEnding.self)
    show(controller, kind: kind) { outcome in
      ending.yield(.closed(outcome))
    }
    afterShowing()
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
    case .closed(let closing):
      await send(.closed(outcome(closing)), on: connection)
    case .disconnected, nil:
      Self.logger.notice("The helper no longer waits for its window")
      controller.callerDisconnected()
    }
  }

  /// Adds the comparison of `diff` to the collection of its origin, or starts one with a window of
  /// its own, and answers `accepted` once its files are kept; answers that it was cancelled if
  /// the window of the collection has closed.
  private func serveCollected(_ diff: SessionRequest.Diff, on connection: SessionConnection) async {
    guard let requestOrigin = diff.origin else {
      await send(.closed(.cancelled), on: connection)
      return
    }
    let origin = CollectionOrigin(requestOrigin)
    collections.removeAll { !$0.files.isReceiving }
    if let joined = collections.first(where: { $0.files.accepts(origin) }) {
      // While the app quits, this is the run whose window just closed, which cancels the rest.
      await add(CollectedFile(diff), to: joined, on: connection)
      return
    }
    guard !isFinishing else {
      await send(.rejected(.quitting), on: connection)
      return
    }
    let collection = OpenCollection(
      files: FileCollection(origin: origin, expectedCount: diff.context.filePosition?.count),
      folder: cache.makeFolder(),
      workingTree: URL(filePath: origin.repository, directoryHint: .isDirectory))
    collections.append(collection)
    guard await keep(CollectedFile(diff), in: collection) else {
      await send(.closed(.cancelled), on: connection)
      return
    }
    let controller: SessionWindowController
    do {
      controller = try await SessionWindowController(
        collection: collection.files, undoManager: UndoManager(), settings: settings)
    } catch {
      presentError(error)
      end(collection)
      await send(.closed(.cancelled), on: connection)
      return
    }
    guard !isFinishing else {
      end(collection)
      await send(.rejected(.quitting), on: connection)
      return
    }
    show(controller, kind: .diff) { [weak self] _ in self?.end(collection) }
    await send(.accepted, on: connection)
  }

  /// Adds `file` to `collection` once it is kept, and answers `accepted`, or that it was
  /// cancelled if the window of the collection has closed.
  private func add(
    _ file: CollectedFile, to collection: OpenCollection, on connection: SessionConnection
  ) async {
    let isAdded = await keep(file, in: collection)
    await send(isAdded ? .accepted : .closed(.cancelled), on: connection)
  }

  /// Keeps a copy of each side of `file` that is not in the working tree and adds it to
  /// `collection`; tells whether it did, which it does not once the window has closed.
  ///
  /// A side that cannot be copied stays where it is, so that the window says it cannot read it
  /// once the file is shown.
  private func keep(_ file: CollectedFile, in collection: OpenCollection) async -> Bool {
    guard !collection.files.isDismissed else { return false }
    var kept = file
    do {
      kept = try await cache.keep(
        file, in: collection.folder, workingTree: collection.workingTree)
    } catch {
      Self.logger.error("Cannot keep \(file.path, privacy: .public): \(error, privacy: .public)")
    }
    guard !collection.files.isDismissed else {
      // The window closed while the files were copied, and its copies went with it.
      cache.remove(collection.folder)
      return false
    }
    collection.files.add(kept)
    return true
  }

  /// Ends `collection` as its window closes: further calls of its origin are cancelled while it
  /// would receive them, and its copies go.
  private func end(_ collection: OpenCollection) {
    collection.files.dismiss()
    cache.remove(collection.folder)
  }

  /// Compares the two folders of `folders` in one window, as File > Compare Folders… does, and
  /// answers success once it closes, which Git waits for before it deletes the folders of a
  /// directory diff; the targets of links that the window writes go with it.
  ///
  /// The folders of `git difftool --dir-diff` name their sides as Git does, and a link of Git to
  /// a file of the working tree stands for that file.
  private func serveFolders(_ folders: SessionRequest.Folders, on connection: SessionConnection)
    async
  {
    guard !isFinishing else {
      await send(.rejected(.quitting), on: connection)
      return
    }
    let linkFolder = cache.makeFolder()
    let collection = FileCollection(
      comparing: FolderPair(left: folders.left, right: folders.right), linkFolder: linkFolder,
      workingTree: folders.isFromGit ? folders.repository : nil)
    defer {
      collection.dismiss()
      cache.remove(linkFolder)
    }
    let controller: SessionWindowController
    do {
      controller = try await SessionWindowController(
        collection: collection, undoManager: UndoManager(), settings: settings)
    } catch {
      presentError(error)
      await send(.closed(.saved), on: connection)
      return
    }
    guard !isFinishing else {
      await send(.rejected(.quitting), on: connection)
      return
    }
    await serveWindow(
      controller, kind: .diff, on: connection, afterShowing: collection.startComparing
    ) { _ in .saved }
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

  /// Reads the files of `request` and opens a window for their merge or comparison, drawn and
  /// started as `settings` say.
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
    for request: SessionRequest, settings: UserSettings
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
          base: merge.base.map { SessionFile(url: $0, label: label) }, a: a, b: b,
          mode: settings.comparisonMode)
        return SessionWindowController(
          session: session, context: context, undoManager: UndoManager(), settings: settings)
      } catch .binaryFile {
        Self.logger.notice("Asking which side of the binary file to take")
        return try await SessionWindowController(
          binaryMerge: BinaryMerge(a: a, b: b, output: merge.output), context: context,
          undoManager: UndoManager(), settings: settings)
      }
    case .diff(let diff):
      let file = { (url: URL, label: String?) in
        SessionFile(url: url, label: label ?? diff.displayPath ?? url.lastPathComponent)
      }
      let (old, new) = (file(diff.left, diff.leftLabel), file(diff.right, diff.rightLabel))
      let context = SessionContext(difftool: DifftoolContext(diff))
      do {
        let session = try await Session.loadDiff(
          old: old, new: new, mode: settings.comparisonMode, ignoring: settings.ignoreRules)
        return SessionWindowController(
          session: session, context: context, undoManager: UndoManager(), settings: settings)
      } catch {
        Self.logger.notice("Showing why the files cannot be compared: \(String(describing: error))")
        return try await SessionWindowController(
          unavailable: UnavailableComparison(old: old, new: new, reason: error), context: context,
          undoManager: UndoManager(), settings: settings)
      }
    case .folders:
      preconditionFailure("The folders of a directory diff are served as a collection")
    }
  }
}

extension SessionRequest {
  /// Whether the request asks for a merge or a comparison.
  fileprivate var kind: Session.Kind {
    switch self {
    case .merge: .merge
    case .diff, .folders: .diff
    }
  }
}

/// The files of one collection, where their copies go, and the working tree whose files need
/// none.
@MainActor
private final class OpenCollection {
  let files: FileCollection
  let folder: URL
  let workingTree: URL

  init(files: FileCollection, folder: URL, workingTree: URL) {
    self.files = files
    self.folder = folder
    self.workingTree = workingTree
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
