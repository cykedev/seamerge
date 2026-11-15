import AppKit
import Testing

@testable import SeamergeUI

/// A window Compare Files for the tests, laid out without a screen, with what it asks and says
/// recorded.
@MainActor
final class CompareFilesFixture {
  let controller: CompareFilesWindowController
  let window: CompareFilesWindow
  let recentComparisons: RecentComparisons
  let delegate = CompareFilesRecorder()
  let panels = PanelRecorder()
  private(set) var announcements: [String] = []

  private let defaults: UserDefaults
  private let suiteName = "app.eiden.seamerge.tests.\(UUID().uuidString)"

  init(
    displayOptions: DisplayOptions = DisplayOptions(),
    integrationStore: (any IntegrationStore)? = nil
  ) throws {
    defaults = try #require(UserDefaults(suiteName: suiteName))
    recentComparisons = RecentComparisons(defaults: defaults)
    window = CompareFilesWindow()
    var announce: (String) -> Void = { _ in }
    controller = CompareFilesWindowController(
      recentComparisons: recentComparisons, displayOptions: displayOptions, panels: panels,
      window: window, integrationStore: integrationStore
    ) { announce($0) }
    announce = { [weak self] in self?.announcements.append($0) }
    controller.delegate = delegate
    window.contentView?.layoutSubtreeIfNeeded()
  }

  isolated deinit {
    defaults.removePersistentDomain(forName: suiteName)
  }

  func field(_ slot: FileSlot) throws -> FileField {
    try #require(controller.fields[slot])
  }

  /// The words below the fields, from left to right.
  var captions: [String] {
    FileSlot.allCases.compactMap { controller.captions[$0]?.stringValue }
  }

  /// Sends the key `characters` to `view` as if it were typed while `view` had the focus.
  func type(_ characters: String, into view: NSView) throws {
    window.makeFirstResponder(view)
    view.keyDown(with: try key(characters))
  }

  func key(_ characters: String, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0))
  }
}

/// A delegate that opens nothing and records what it was asked to open.
@MainActor
final class CompareFilesRecorder: CompareFilesWindowControllerDelegate {
  /// The error opening fails with, if it should.
  var failure: (any Error)?

  private(set) var opened: [FileComparison] = []
  private let (openings, openingSink) = AsyncStream.makeStream(of: Void.self)

  func compareFilesWindowController(
    _ controller: CompareFilesWindowController, open comparison: FileComparison
  ) async throws {
    opened.append(comparison)
    defer { openingSink.yield() }
    if let failure {
      throw failure
    }
  }

  /// Waits until the window has taken the answer to the next opening.
  ///
  /// A failing opening is done once its sheet is dismissed, which ``PanelRecorder`` does at once.
  func nextOpening() async {
    var iterator = openings.makeAsyncIterator()
    await iterator.next()
  }
}

/// Panels that answer as the test says: a chooser that answers with the next of its files, and a
/// sheet of a failure that is dismissed at once.
@MainActor
final class PanelRecorder: CompareFilesPanels {
  var files: [URL] = []
  private(set) var roles: [String] = []
  private(set) var fileChoices: [FileChoice] = []
  private(set) var failures: [String] = []
  private let (choices, choiceSink) = AsyncStream.makeStream(of: Void.self)
  private let (shownFailures, failureSink) = AsyncStream.makeStream(of: Void.self)

  func chooseFile(_ choice: FileChoice, for role: String, in window: NSWindow) async -> URL? {
    roles.append(role)
    fileChoices.append(choice)
    defer { choiceSink.yield() }
    return files.isEmpty ? nil : files.removeFirst()
  }

  func showFailure(_ error: any Error, in window: NSWindow) async {
    failures.append(error.localizedDescription)
    failureSink.yield()
  }

  /// Waits until the window has taken the answer to the next question for a file.
  ///
  /// The window takes the answer on the turn of the main actor that gave it, before this
  /// returns.
  func nextChoice() async {
    var iterator = choices.makeAsyncIterator()
    await iterator.next()
  }

  /// Waits until the window has shown the next failure.
  func nextFailure() async {
    var iterator = shownFailures.makeAsyncIterator()
    await iterator.next()
  }
}

/// Files on disk in a folder of their own, for the tests of Compare Files.
struct SampleFiles: ~Copyable {
  let folder: URL

  init() throws {
    folder = FileManager.default.temporaryDirectory.appending(
      path: "CompareFiles-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  deinit {
    do {
      try FileManager.default.removeItem(at: folder)
    } catch {
      Issue.record(error, "The sample files could not be removed")
    }
  }

  /// Writes a file named `name` and returns its URL.
  func file(_ name: String) throws -> URL {
    let url = folder.appending(path: name)
    try Data("\(name)\n".utf8).write(to: url)
    return url
  }

  /// Makes a folder named `name` and returns its URL.
  func subfolder(_ name: String) throws -> URL {
    let url = folder.appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}

/// A drag in the test: files on a pasteboard of its own, or a field of a window.
@MainActor
final class DragInTest: NSObject, @MainActor NSDraggingInfo {
  let draggingPasteboard: NSPasteboard
  let draggingSource: Any?

  init(files: [URL]) {
    draggingPasteboard = NSPasteboard.withUniqueName()
    draggingPasteboard.clearContents()
    draggingPasteboard.writeObjects(files.map { $0 as NSURL })
    draggingSource = nil
  }

  init(field: FileField) {
    draggingPasteboard = NSPasteboard.withUniqueName()
    draggingSource = field
  }

  var draggingDestinationWindow: NSWindow? { nil }
  var draggingSourceOperationMask: NSDragOperation { [.copy, .move] }
  var draggingLocation: NSPoint { .zero }
  var draggedImageLocation: NSPoint { .zero }
  var draggedImage: NSImage? { nil }
  var draggingSequenceNumber: Int { 1 }
  var draggingFormation: NSDraggingFormation = .default
  var animatesToDestination = false
  var numberOfValidItemsForDrop = 0
  var springLoadingHighlight: NSSpringLoadingHighlight { .none }

  func slideDraggedImage(to screenPoint: NSPoint) {}

  func enumerateDraggingItems(
    options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
    classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
  ) {}

  func resetSpringLoading() {}
}
