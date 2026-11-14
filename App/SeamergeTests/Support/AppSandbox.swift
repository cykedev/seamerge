import AppKit
import Foundation
import SeamergeUI
import SessionIPC
import Testing

/// A temporary folder for one test of the app: its socket, its user defaults and the files it
/// merges.
@MainActor
final class AppSandbox {
  let folder: URL
  let defaults: UserDefaults
  /// Records the alerts the app would show and whether it would hide.
  let presenter = PresenterRecorder()
  private let suiteName = "app.eiden.seamerge.tests.\(UUID().uuidString)"

  init() throws {
    // Socket paths are limited to 103 bytes, so the folder name stays short.
    folder = FileManager.default.temporaryDirectory.appending(
      path: "SM-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defaults = try #require(UserDefaults(suiteName: suiteName))
  }

  isolated deinit {
    defaults.removePersistentDomain(forName: suiteName)
    do {
      try FileManager.default.removeItem(at: folder)
    } catch {
      Issue.record(error, "The sandbox could not be removed")
    }
  }

  /// Settings of Git and Tower inside the sandbox: its folder is the home folder, and Git reads
  /// a configuration file there instead of the user's.
  var integrationStore: SystemIntegrationStore {
    var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_CONFIG_GLOBAL"] = folder.appending(path: ".gitconfig").path
    return SystemIntegrationStore(
      bundle: Bundle.main.bundleURL, home: folder, environment: environment)
  }

  /// Where the app in the test listens for the helper.
  var socketURL: URL { folder.appending(path: "s.sock") }

  /// Records the errors the app would show.
  var presentError: (any Error) -> Void {
    { [presenter] error in presenter.present(error) }
  }

  /// A coordinator that listens at the socket of the sandbox, with `recorder` as its delegate.
  func startCoordinator(recorder: WindowRecorder) throws -> SessionCoordinator {
    let coordinator = SessionCoordinator(socketURL: socketURL, presentError: presentError)
    coordinator.delegate = recorder
    try coordinator.start()
    return coordinator
  }

  /// Writes `text` into a file named `name` and returns its URL.
  @discardableResult
  func file(_ name: String, _ text: String = "line\n") throws -> URL {
    let url = folder.appending(path: name)
    try Data(text.utf8).write(to: url)
    return url
  }

  /// A merge of three small files into `story.txt`, as the helper would send it.
  func mergeRequest(context: SessionRequest.MergeContext = .init()) throws -> SessionRequest {
    .merge(
      SessionRequest.Merge(
        base: try file("story_BASE.txt", "one\ntwo\nthree\n"),
        local: try file("story_LOCAL.txt", "one\nmine\nthree\n"),
        remote: try file("story_REMOTE.txt", "one\ntheirs\nthree\n"),
        output: try file("story.txt", "one\n<<<<<<< HEAD\nmine\n=======\ntheirs\n>>>>>>> b\n"),
        context: context))
  }

  /// A comparison as `git difftool` asks for it: the second of three files, a temporary copy
  /// before the change on the left and the working copy on the right.
  func comparisonRequest() throws -> SessionRequest {
    .diff(
      SessionRequest.Diff(
        left: try file("story_LEFT.txt", "one\ntwo\nthree\n"),
        right: try file("story.txt", "one\nchanged\nthree\n"), displayPath: "src/story.txt",
        context: SessionRequest.DiffContext(
          leftRole: .before, rightRole: .workingCopy,
          filePosition: SessionRequest.FilePosition(number: 2, count: 3))))
  }
}

/// A presenter that records what the app would show and do instead.
@MainActor
final class PresenterRecorder: AppPresenter {
  private(set) var errors: [any Error] = []
  private(set) var hideCount = 0

  /// The errors shown, as their messages.
  var messages: [String] { errors.map(\.localizedDescription) }

  func present(_ error: any Error) {
    errors.append(error)
  }

  func hide() {
    hideCount += 1
  }
}

/// A delegate of the coordinator that hands each window that opens to the test.
@MainActor
final class WindowRecorder: SessionCoordinatorDelegate {
  private var count = 0
  private var opened: [SessionWindowController] = []
  private var waiter: CheckedContinuation<Void, Never>?
  private(set) var changeCount = 0

  func sessionCoordinatorDidChangeWindows(_ coordinator: SessionCoordinator) {
    changeCount += 1
    let controllers = coordinator.windowControllers
    if controllers.count > count, let newest = controllers.last {
      opened.append(newest)
      waiter?.resume()
      waiter = nil
    }
    count = controllers.count
  }

  /// Waits for the next window that opens.
  func nextOpened() async -> SessionWindowController {
    if opened.isEmpty {
      await withCheckedContinuation { waiter = $0 }
    }
    return opened.removeFirst()
  }
}

/// Runs `request` against the app in the test, as the helper does, in a task of its own.
func perform(_ request: SessionRequest, at socketURL: URL) -> Task<SessionReply, any Error> {
  Task {
    try await SessionClient(socketURL: socketURL).perform(request)
  }
}

/// The height the header above the result of `window` takes, which grows by a line while it
/// says that Git no longer waits.
@MainActor
func resultHeaderHeight(in window: NSWindow) -> CGFloat? {
  func find(in view: NSView) -> NSView? {
    if String(describing: type(of: view)).contains("ResultHeaderView") {
      return view
    }
    return view.subviews.lazy.compactMap(find).first
  }
  return window.contentView.flatMap(find)?.fittingSize.height
}
