import AppKit
import SeamergeUI
import SessionIPC
import Testing

/// Text from the clipboard in the app: Edit > Paste in the welcome window and its sheet, the
/// window it opens, which Open Recent never offers, and the copies of the text, which go with
/// the window and, after a crash, with the next launch.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ClipboardComparisonTests {
  /// The item Edit > Paste of the menu bar of `delegate`.
  private func pasteItem(of delegate: AppDelegate) throws -> NSMenuItem {
    let items = delegate.mainMenu.menu.items.compactMap(\.submenu).flatMap(\.items)
    return try #require(items.first { $0.action == #selector(NSText.paste(_:)) })
  }

  /// Sends Paste to `target` as the menu bar does once it has checked that the item is valid.
  private func paste(
    with item: NSMenuItem, to target: NSResponder
  ) throws {
    let validation = try #require(target as? any NSUserInterfaceValidations)
    #expect(validation.validateUserInterfaceItem(item))
    #expect(NSApplication.shared.sendAction(#selector(NSText.paste(_:)), to: target, from: item))
  }

  @Test func pasteComparesTextFromTheClipboardThatOpenRecentNeverOffers() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox)
    let recorder = WindowRecorder()
    delegate.coordinator.delegate = recorder
    let item = try pasteItem(of: delegate)
    let welcome = delegate.welcome()
    let file = try sandbox.file("config.toml", "port = 80\n")

    sandbox.pasteboard.clearContents()
    sandbox.pasteboard.setString("port = 8080\n", forType: .string)
    try paste(with: item, to: welcome)
    let window = try #require(welcome.window)
    let sheet = try #require(window.attachedSheet?.windowController)
    #expect(fileFields(in: window).map(\.value) == ["Clipboard, 1 line", "empty"])

    sandbox.pasteboard.clearContents()
    sandbox.pasteboard.writeObjects([file as NSURL])
    try paste(with: item, to: sheet)
    #expect(
      fileFields(in: window).map(\.value) == ["Clipboard, 1 line", fileFieldValue(of: file)])
    let compare = try #require(
      window.attachedSheet?.contentView.flatMap { button(titled: "Compare", in: $0) })
    compare.performClick(nil)
    let opened = await recorder.nextOpened()

    #expect(opened.window?.title == "Clipboard ↔ config.toml")
    #expect(try sandbox.keptPastedTexts.count == 1)
    #expect(delegate.recentComparisons.comparisons.isEmpty)
    let menu = delegate.recentComparisonsMenu.menu
    delegate.recentComparisonsMenu.menuNeedsUpdate(menu)
    #expect(!menu.items.contains { $0.title.contains("Clipboard") })

    opened.close()
    #expect(try sandbox.keptPastedTexts.isEmpty)
    await delegate.coordinator.finish()
  }

  @Test func pasteIsInvalidInTheWelcomeWindowWithoutTextOrFiles() throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox)
    let item = try pasteItem(of: delegate)
    let image = try #require(NSImage(systemSymbolName: "doc", accessibilityDescription: nil))

    sandbox.pasteboard.clearContents()
    sandbox.pasteboard.writeObjects([image])

    #expect(!delegate.welcome().validateUserInterfaceItem(item))
    delegate.welcome().close()
  }

  @Test func launchClearsOutPastedTextThatACrashLeftBehind() async throws {
    let sandbox = try AppSandbox()
    let folder = sandbox.folder.appending(path: "Clipboard", directoryHint: .isDirectory)
    for (name, age) in [("leftover", -3600.0), ("fresh", 3600.0)] {
      let copy = folder.appending(path: name, directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
      try Data("text\n".utf8).write(to: copy.appending(path: "Clipboard.txt"))
      try FileManager.default.setAttributes(
        [.creationDate: Date.now.addingTimeInterval(age)], ofItemAtPath: copy.path)
    }
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])

    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    await delegate.clearingPastedTexts?.value

    #expect(try sandbox.keptPastedTexts == ["fresh"])
    await delegate.coordinator.finish()
  }

  /// The button titled `title` in `view` or below it.
  private func button(titled title: String, in view: NSView) -> NSButton? {
    if let button = view as? NSButton, button.title == title {
      return button
    }
    return view.subviews.lazy.compactMap { button(titled: title, in: $0) }.first
  }

  private func makeDelegate(
    in sandbox: AppSandbox, arguments: [String] = ["Seamerge", HelperLaunch.argument]
  ) -> AppDelegate {
    AppDelegate(
      arguments: arguments, defaults: sandbox.defaults, socketURL: sandbox.socketURL,
      collectionCache: sandbox.collectionCache, workStore: sandbox.workStore,
      pasteboard: sandbox.pasteboard, pastedTextCache: sandbox.pastedTextCache,
      presenter: sandbox.presenter, integrationStore: sandbox.integrationStore,
      commandLineTool: sandbox.commandLineTool,
      makeSoftwareUpdater: { _ in SoftwareUpdaterDouble() }, bundle: sandbox.bundle,
      updateServices: {})
  }
}
