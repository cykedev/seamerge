import AppKit
import SeamergeUI
import Testing

/// The service Compare with Seamerge: how the app declares and registers it, and what it opens
/// for each kind of selection in the Finder.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct FinderServiceTests {
  @Test func informationOfTheAppOffersTheServiceForFilesAndFoldersWithoutAShortcut() throws {
    let info = try #require(
      NSDictionary(contentsOf: try builtApp().appending(path: "Contents/Info.plist")))
    let services = try #require(info["NSServices"] as? [[String: Any]])
    let service = try #require(services.first)

    #expect(services.count == 1)
    #expect((service["NSMenuItem"] as? [String: String])?["default"] == "Compare with Seamerge")
    #expect(service["NSPortName"] as? String == "Seamerge")
    #expect(service["NSSendFileTypes"] as? [String] == ["public.data", "public.folder"])
    #expect(service["NSRequiredContext"] is [String: Any])
    #expect(service["NSKeyEquivalent"] == nil)
    #expect(service["NSReturnTypes"] == nil)
    let message = try #require(service["NSMessage"] as? String)
    #expect(AppDelegate.instancesRespond(to: Selector("\(message):userData:error:")))
  }

  @Test func appServesTheServiceAndRegistersItOnlyFromAFolderOfApplications() async throws {
    let sandbox = try AppSandbox()
    let home = FileManager.default.homeDirectoryForCurrentUser
    for (bundle, registers) in [
      (URL(filePath: "/Applications/Seamerge.app"), true),
      (home.appending(path: "Applications/Seamerge.app"), true),
      (URL(filePath: "/Volumes/Seamerge/Seamerge.app"), false),
      (home.appending(path: "Downloads/Seamerge.app"), false),
    ] {
      var updates = 0
      let delegate = makeDelegate(in: sandbox, bundle: bundle) { updates += 1 }

      delegate.hasReceivedTask = true
      delegate.applicationDidFinishLaunching(launch)

      #expect(NSApplication.shared.servicesProvider as? AppDelegate === delegate)
      #expect(updates == (registers ? 1 : 0), "\(bundle.path)")
      await delegate.startWindowTask?.value
      await delegate.coordinator.finish()
    }
  }

  @Test func launchForTheServiceLeavesNoWelcomeWindowBehindWhatItOpens() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox)
    let recorder = WindowRecorder()
    delegate.coordinator.delegate = recorder
    let files = [try sandbox.file("a.txt", "a\n"), try sandbox.file("b.txt", "b\n")]

    delegate.applicationDidFinishLaunching(launch)
    callService(of: delegate, with: files)
    await delegate.startWindowTask?.value
    let opened = await recorder.nextOpened()

    #expect(delegate.welcomeWindowController == nil)
    opened.close()
    await delegate.coordinator.finish()
  }

  @Test func launchWithFilesToOpenShowsThemInTheSheetCompareFiles() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox)
    let file = try sandbox.file("a.txt")

    delegate.application(.shared, open: [file])
    delegate.applicationDidFinishLaunching(launch)
    await delegate.startWindowTask?.value

    let window = try #require(delegate.welcomeWindowController?.window)
    defer { window.close() }
    #expect(window.isVisible)
    #expect(fileFields(in: window).first?.value == fileFieldValue(of: file))
    await delegate.coordinator.finish()
  }

  @Test func launchWithASessionWindowAlreadyShowingShowsNoWelcomeWindow() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox)
    let recorder = WindowRecorder()
    delegate.coordinator.delegate = recorder

    try await delegate.coordinator.open(
      FileComparison(left: try sandbox.file("x.txt"), right: try sandbox.file("y.txt")))
    let restored = await recorder.nextOpened()
    delegate.applicationDidFinishLaunching(launch)
    await delegate.startWindowTask?.value

    #expect(delegate.welcomeWindowController == nil)
    restored.close()
    await delegate.coordinator.finish()
  }

  @Test func twoFilesOnThePasteboardOpenAtOnceWithTheOlderOnTheLeftBesideASession() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox)
    let recorder = WindowRecorder()
    delegate.coordinator.delegate = recorder
    let older = try sandbox.file("old.txt", "a\n")
    let newer = try sandbox.file("new.txt", "b\n")
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1_000_000)],
      ofItemAtPath: older.path(percentEncoded: false))
    try await delegate.coordinator.open(
      FileComparison(left: try sandbox.file("x.txt"), right: try sandbox.file("y.txt")))
    let session = await recorder.nextOpened()

    let message = callService(of: delegate, with: [newer, older])
    let opened = await recorder.nextOpened()

    #expect(opened.window?.title == "old.txt ↔ new.txt")
    #expect(sandbox.presenter.activationCount == 1)
    #expect(message == nil)
    #expect(session.window?.isVisible == true)
    #expect(delegate.coordinator.windowControllers.count == 2)
    #expect(
      delegate.recentComparisons.comparisons == [FileComparison(left: older, right: newer)])
    #expect(delegate.welcomeWindowController == nil)
    opened.close()
    session.close()
  }

  @Test func twoFoldersOpenAtOnce() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox)
    let recorder = WindowRecorder()
    delegate.coordinator.delegate = recorder
    let folders = try sandbox.folders()

    await delegate.compare(.comparison(FileComparison(folders: folders)))
    let opened = await recorder.nextOpened()

    #expect(opened.collection?.folders == folders)
    #expect(delegate.welcomeWindowController == nil)
    opened.close()
  }

  @Test func oneEntryGoesLeftWithTheFocusOnRight() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox)
    let file = try sandbox.file("a.txt")

    await delegate.compare(.one(file))

    let window = try #require(delegate.welcomeWindowController?.window)
    defer { window.close() }
    #expect(window.isVisible)
    #expect(fileFields(in: window).map(\.value) == [fileFieldValue(of: file), "empty"])
    let sheet = try #require(window.attachedSheet)
    #expect((sheet.firstResponder as? NSView)?.accessibilityLabel() == "Right")
  }

  @Test func threeFilesFillEveryFieldToShowTheirRolesBeforeTheMerge() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox)
    let files = [try sandbox.file("a.txt"), try sandbox.file("o.txt"), try sandbox.file("b.txt")]

    await delegate.compare(.threeFiles(files))

    let window = try #require(delegate.welcomeWindowController?.window)
    defer { window.close() }
    #expect(fileFields(in: window).map(\.label) == ["A", "Base", "B"])
    #expect(
      fileFields(in: window).map(\.value)
        == files.map(fileFieldValue(of:)))
    #expect(delegate.coordinator.windowControllers.isEmpty)
  }

  @Test func selectionThatIsNotComparedSaysWhatSeamergeCompares() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox)

    await delegate.compare(.unsupported)

    let window = try #require(delegate.welcomeWindowController?.window)
    defer { window.close() }
    #expect(window.isVisible)
    #expect(
      labelTexts(in: window).contains("Seamerge compares two or three files, or two folders."))
    #expect(fileFields(in: window).map(\.value) == ["empty", "empty"])
  }

  @Test func filesThatCannotBeOpenedStandInTheSheetCompareFilesWithTheReason() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox)
    let binary = try sandbox.file("image.png", "\u{0}\u{1}PNG\u{0}")
    let text = try sandbox.file("text.txt")

    await delegate.compare(.comparison(FileComparison(left: binary, right: text)))

    let window = try #require(delegate.welcomeWindowController?.window)
    defer { window.close() }
    let sheet = try #require(window.attachedSheet)
    var turns = 0
    while sheet.attachedSheet == nil && turns < 1000 {
      await Task.yield()
      turns += 1
    }
    let alert = try #require(sheet.attachedSheet)
    #expect(window.isVisible)
    #expect(fileFields(in: window).map(\.label) == ["Left", "Right"])
    #expect(fileFields(in: window).first?.value == fileFieldValue(of: binary))
    #expect(delegate.coordinator.windowControllers.isEmpty)
    #expect(delegate.recentComparisons.comparisons.isEmpty)
    #expect(sandbox.presenter.errors.isEmpty)
    sheet.endSheet(alert)
    window.endSheet(sheet)
  }

  /// The notification that the app has finished launching.
  private var launch: Notification {
    Notification(name: NSApplication.didFinishLaunchingNotification)
  }

  /// Hands `urls` to the service of `delegate` on a pasteboard of their own, as the Finder does,
  /// and returns the error message the service gave back, if any.
  @discardableResult
  private func callService(of delegate: AppDelegate, with urls: [URL]) -> NSString? {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.writeObjects(urls.map { $0 as NSURL })
    var message: NSString?
    withUnsafeMutablePointer(to: &message) { pointer in
      delegate.compareWithSeamerge(
        pasteboard, userData: nil, error: AutoreleasingUnsafeMutablePointer(pointer))
    }
    pasteboard.releaseGlobally()
    return message
  }

  /// The app that the scheme builds next to the tests.
  private func builtApp() throws -> URL {
    let app = Bundle(for: AppDelegate.self).bundleURL.deletingLastPathComponent()
      .appending(path: "Seamerge.app")
    try #require(FileManager.default.fileExists(atPath: app.path), "No app at \(app.path)")
    return app
  }

  private func makeDelegate(
    in sandbox: AppSandbox, bundle: URL? = nil, updateServices: @escaping @MainActor () -> Void = {}
  ) -> AppDelegate {
    AppDelegate(
      arguments: ["Seamerge"], defaults: sandbox.defaults, socketURL: sandbox.socketURL,
      collectionCache: sandbox.collectionCache, workStore: sandbox.workStore,
      presenter: sandbox.presenter,
      integrationStore: sandbox.integrationStore, commandLineTool: sandbox.commandLineTool,
      makeSoftwareUpdater: { _ in SoftwareUpdaterDouble() }, bundle: bundle ?? sandbox.bundle,
      updateServices: updateServices)
  }
}
