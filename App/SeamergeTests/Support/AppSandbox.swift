import AppKit
import FolderCompare
import Foundation
import Integration
import SeamergeUI
import SessionIPC
import Testing

/// A temporary folder for one test of the app: its socket, its user defaults and the files it
/// merges.
///
/// From the first sandbox on, every window the process shows is transparent, so that the
/// windows of the tests stay out of sight.
@MainActor
final class AppSandbox {
  let folder: URL
  let defaults: UserDefaults
  /// The settings of the app in the test, kept in its user defaults.
  let settings: UserSettings
  /// Records the alerts the app would show and whether it would hide.
  let presenter = PresenterRecorder()
  /// Where the app in the test runs from: outside the folders of applications, so that it never
  /// registers its service with the system.
  let bundle = URL(filePath: "/Volumes/Build/Seamerge.app")
  private let suiteName = "app.eiden.seamerge.tests.\(UUID().uuidString)"
  /// The provider of services before the test, which a launch in the test replaces.
  private let servicesProvider = NSApplication.shared.servicesProvider

  init() throws {
    TransparentWindows.turnOn()
    // Socket paths are limited to 103 bytes, so the folder name stays short.
    folder = FileManager.default.temporaryDirectory.appending(
      path: "SM-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defaults = try #require(UserDefaults(suiteName: suiteName))
    settings = UserSettings(defaults: defaults)
  }

  isolated deinit {
    pasteboard.releaseGlobally()
    NSApplication.shared.servicesProvider = servicesProvider
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

  /// The seamerge command of the app in the test, with its link and Homebrew inside the
  /// sandbox.
  var commandLineTool: CommandLineTool {
    CommandLineTool(
      bundle: Bundle.main.bundleURL, link: folder.appending(path: "bin/seamerge"),
      homebrewPrefixes: [folder.appending(path: "homebrew")])
  }

  /// Where the app in the test keeps the copies of collected files.
  var collectionCache: CollectionCache {
    CollectionCache(folder: folder.appending(path: "Collections", directoryHint: .isDirectory))
  }

  /// Where the app in the test keeps the work of unfinished merges, which the sandbox removes
  /// with its folder.
  lazy var workStore = MergeWorkStore(
    folder: folder.appending(path: "Merges", directoryHint: .isDirectory))

  /// The files in the folder of work of the app in the test.
  var keptWorkFiles: [String] {
    get throws {
      let url = folder.appending(path: "Merges", directoryHint: .isDirectory)
      guard FileManager.default.fileExists(atPath: url.path) else { return [] }
      return try FileManager.default.contentsOfDirectory(atPath: url.path)
    }
  }

  /// The clipboard of the app in the test, which no other test and no other app uses.
  let pasteboard = NSPasteboard.withUniqueName()

  /// Where the app in the test keeps the copies of text pasted from its clipboard.
  var pastedTextCache: PastedTextCache {
    PastedTextCache(folder: folder.appending(path: "Clipboard", directoryHint: .isDirectory))
  }

  /// The copies of pasted text that the app in the test keeps, each in a folder of its own.
  var keptPastedTexts: [String] {
    get throws {
      let url = folder.appending(path: "Clipboard", directoryHint: .isDirectory)
      guard FileManager.default.fileExists(atPath: url.path) else { return [] }
      return try FileManager.default.contentsOfDirectory(atPath: url.path)
    }
  }

  /// Where the app in the test listens for the helper.
  var socketURL: URL { folder.appending(path: "s.sock") }

  /// Records the errors the app would show.
  var presentError: (any Error) -> Void {
    { [presenter] error in presenter.present(error) }
  }

  /// A coordinator that listens at the socket of the sandbox, with `recorder` as its delegate.
  func startCoordinator(recorder: WindowRecorder) throws -> SessionCoordinator {
    let coordinator = SessionCoordinator(
      socketURL: socketURL, cache: collectionCache, settings: settings, workStore: workStore,
      presentError: presentError)
    coordinator.delegate = recorder
    try coordinator.start()
    return coordinator
  }

  /// Two folders named Old and New, each with a file that differs.
  func folders() throws -> FolderPair {
    let pair = FolderPair(
      left: folder.appending(path: "Old", directoryHint: .isDirectory),
      right: folder.appending(path: "New", directoryHint: .isDirectory))
    for (url, text) in [(pair.left, "old\n"), (pair.right, "new\n")] {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      try Data(text.utf8).write(to: url.appending(path: "a.txt"))
    }
    return pair
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
  private(set) var activationCount = 0

  /// The errors shown, as their messages.
  var messages: [String] { errors.map(\.localizedDescription) }

  func present(_ error: any Error) {
    errors.append(error)
  }

  func hide() {
    hideCount += 1
  }

  func activate() {
    activationCount += 1
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

/// Waits until the merge window of `controller` takes the commands of its lines, as it does once
/// the comparison of its files is ready and shown.
@MainActor
func waitUntilFilled(_ controller: SessionWindowController) async {
  let item = NSMenuItem(title: "", action: SessionCommand.toggleBase.action, keyEquivalent: "")
  while !controller.validateUserInterfaceItem(item) {
    await Task.yield()
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
