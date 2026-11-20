import AppKit
import Integration
import Testing

@testable import SeamergeUI

/// A sheet of files for the tests, laid out without a screen and without a window to hang on,
/// with what it opens, asks and says recorded.
@MainActor
final class CompareFilesFixture {
  let controller: CompareFilesWindowController
  let window: CompareFilesWindow
  let opener = ComparisonRecorder()
  let panels = PanelRecorder()
  private(set) var announcements: [String] = []

  init(
    _ purpose: CompareFilesWindowController.Purpose = .compare,
    displayOptions: DisplayOptions = DisplayOptions()
  ) {
    WindowAnimations.turnOff()
    TransparentWindows.turnOn()
    window = CompareFilesWindow()
    var announce: (String) -> Void = { _ in }
    controller = CompareFilesWindowController(
      purpose: purpose, displayOptions: displayOptions, panels: panels, window: window
    ) { announce($0) }
    announce = { [weak self] in self?.announcements.append($0) }
    controller.onOpen = { [opener] in try await opener.open($0) }
    window.contentView?.layoutSubtreeIfNeeded()
  }

  func field(_ slot: FileSlot) throws -> FileField {
    try #require(controller.fields[slot])
  }

  /// The words below the fields, from left to right.
  var captions: [String] {
    controller.selection.slots.compactMap { controller.captions[$0]?.stringValue }
  }

  /// The files in the fields, from left to right.
  var files: [URL?] {
    controller.selection.slots.map { controller.selection[$0] }
  }

  /// Sends the key `characters` to `view` as if it were typed while `view` had the focus.
  func type(_ characters: String, into view: NSView) throws {
    window.makeFirstResponder(view)
    view.keyDown(with: try keyEvent(characters, in: window))
  }
}

/// A welcome window for the tests, laid out without a screen, with what it opens, asks and says
/// recorded.
@MainActor
final class WelcomeFixture {
  let controller: WelcomeWindowController
  let window: WelcomeWindow
  let recentComparisons: RecentComparisons
  let opener = ComparisonRecorder()
  let panels = PanelRecorder()
  private(set) var announcements: [String] = []

  private let defaults: UserDefaults
  private let suiteName = "app.eiden.seamerge.tests.\(UUID().uuidString)"
  private let (closes, closeSink) = AsyncStream.makeStream(of: Void.self)
  private var closeObserver: (any NSObjectProtocol)?

  init(
    displayOptions: DisplayOptions = DisplayOptions(),
    integrationStore: (any IntegrationStore)? = nil
  ) throws {
    WindowAnimations.turnOff()
    TransparentWindows.turnOn()
    defaults = try #require(UserDefaults(suiteName: suiteName))
    recentComparisons = RecentComparisons(defaults: defaults)
    window = WelcomeWindow()
    var announce: (String) -> Void = { _ in }
    controller = WelcomeWindowController(
      recentComparisons: recentComparisons, displayOptions: displayOptions, panels: panels,
      window: window, integrationStore: integrationStore,
      icon: NSImage(named: NSImage.applicationIconName) ?? NSImage(), version: "0.6.0"
    ) { announce($0) }
    announce = { [weak self] in self?.announcements.append($0) }
    controller.delegate = opener
    window.contentView?.layoutSubtreeIfNeeded()
    // Observed from the start, so that a window that closes while the test still waits for
    // something else is not missed.
    closeObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: nil
    ) { [closeSink] _ in closeSink.yield() }
  }

  isolated deinit {
    closeObserver.map(NotificationCenter.default.removeObserver)
    window.close()
    defaults.removePersistentDomain(forName: suiteName)
  }

  /// Waits until the window closes, or returns at once if it has closed since the last call.
  func nextClose() async {
    var iterator = closes.makeAsyncIterator()
    await iterator.next()
  }

  /// The sheet of files on the window, which the test expects to be there.
  func sheet() throws -> CompareFilesWindowController {
    try #require(controller.filesSheet)
  }

  /// The files in the fields of the sheet, from left to right.
  func files() throws -> [URL?] {
    let sheet = try sheet()
    return sheet.selection.slots.map { sheet.selection[$0] }
  }

  /// The words below the fields of the sheet, from left to right.
  func captions() throws -> [String] {
    let sheet = try sheet()
    return sheet.selection.slots.compactMap { sheet.captions[$0]?.stringValue }
  }
}

extension WelcomeFixture {
  /// Draws the window with its sheet of files in front, where the sheet hangs: at the top of the
  /// window, in the middle; and writes the picture as `name`.
  func picture(look: Look, named name: String) throws {
    let window = self.window
    let sheetWindow = try #require(sheet().window)
    for window in [window, sheetWindow] {
      window.colorSpace = .sRGB
      window.appearance = look.appearance
      window.contentView?.layoutSubtreeIfNeeded()
    }
    let bitmap = try Rendering.bitmap(of: window)
    let content = try #require(sheetWindow.contentView)
    let sheetBitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
    content.cacheDisplay(in: content.bounds, to: sheetBitmap)

    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    let frame = try #require(window.contentView?.superview).bounds
    let size = content.bounds.size
    let rect = CGRect(
      x: (frame.width - size.width) / 2, y: frame.height - size.height - 28, width: size.width,
      height: size.height)
    let outline = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = CGSize(width: 0, height: -8)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    var background = NSColor.windowBackgroundColor
    look.appearance.performAsCurrentDrawingAppearance {
      background = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? background
    }
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    background.setFill()
    outline.fill()
    NSGraphicsContext.restoreGraphicsState()
    outline.addClip()
    sheetBitmap.draw(
      in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    try Rendering.write(bitmap, named: name)
  }
}

/// The key `characters` as if it were typed in `window`.
@MainActor
func keyEvent(
  _ characters: String, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow
) throws -> NSEvent {
  try #require(
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
      windowNumber: window.windowNumber, context: nil, characters: characters,
      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0))
}

/// Opens nothing and records what it was asked to open, from a welcome window or a sheet.
@MainActor
final class ComparisonRecorder: WelcomeWindowControllerDelegate {
  /// The error opening fails with, if it should.
  var failure: (any Error)?

  private(set) var opened: [FileComparison] = []
  private let (openings, openingSink) = AsyncStream.makeStream(of: Void.self)

  func open(_ comparison: FileComparison) async throws {
    opened.append(comparison)
    defer { openingSink.yield() }
    if let failure {
      throw failure
    }
  }

  func welcomeWindowController(
    _ controller: WelcomeWindowController, open comparison: FileComparison
  ) async throws {
    try await open(comparison)
  }

  /// Waits until the next opening has been answered.
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

/// Files on disk in a folder of their own, for the tests of the welcome window and its sheets.
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
