import AppKit
import GitSupport
import SeamergeUI
import SessionIPC
import Testing

/// Comparisons with an origin, as `git difftool` sends them through `seamerge diff --collect`:
/// which window they join, what they answer, and the copies of their files.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct CollectionCoordinatorTests {
  @Test func comparisonsOfOneOriginJoinOneWindowAndEndAtOnce() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)

    let first = try await perform(sandbox.collected("a.txt", number: 1), at: sandbox.socketURL)
      .value
    let second = try await perform(sandbox.collected("b.txt", number: 2), at: sandbox.socketURL)
      .value

    #expect(first == .accepted)
    #expect(second == .accepted)
    let controller = await recorder.nextOpened()
    #expect(coordinator.windowControllers.count == 1)
    #expect(controller.collection?.files.map(\.path) == ["a.txt", "b.txt"])
    #expect(controller.window?.isVisible == true)
    await coordinator.finish()
  }

  @Test func comparisonOfAnotherOriginOpensAWindowOfItsOwn() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)

    _ = try await perform(sandbox.collected("a.txt", number: 1), at: sandbox.socketURL).value
    _ = try await perform(
      sandbox.collected("b.txt", number: 1, repository: "/other"), at: sandbox.socketURL
    ).value

    _ = await recorder.nextOpened()
    _ = await recorder.nextOpened()
    #expect(coordinator.windowControllers.count == 2)
    await coordinator.finish()
  }

  @Test func comparisonAfterEveryNumberCameOpensANewWindow() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    for number in 1...3 {
      _ = try await perform(
        sandbox.collected("f\(number).txt", number: number), at: sandbox.socketURL
      ).value
    }

    _ = try await perform(sandbox.collected("again.txt", number: 1), at: sandbox.socketURL).value

    _ = await recorder.nextOpened()
    let second = await recorder.nextOpened()
    #expect(second.collection?.files.map(\.path) == ["again.txt"])
    await coordinator.finish()
  }

  @Test func simultaneousComparisonsKeepTheOrderOfGit() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)

    let calls = try [3, 1, 2].map { number in
      perform(try sandbox.collected("f\(number).txt", number: number), at: sandbox.socketURL)
    }
    for call in calls {
      #expect(try await call.value == .accepted)
    }

    let controller = await recorder.nextOpened()
    #expect(coordinator.windowControllers.count == 1)
    #expect(controller.collection?.files.map(\.path) == ["f1.txt", "f2.txt", "f3.txt"])
    await coordinator.finish()
  }

  @Test func comparisonsAfterTheWindowClosedEndWithOneAndOpenNothing() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    _ = try await perform(sandbox.collected("a.txt", number: 1), at: sandbox.socketURL).value
    let controller = await recorder.nextOpened()

    controller.window?.close()
    let late = try await perform(sandbox.collected("b.txt", number: 2), at: sandbox.socketURL)
      .value

    #expect(late == .closed(.cancelled))
    #expect(coordinator.windowControllers.isEmpty)
    await coordinator.finish()
  }

  @Test func fileStaysReadableAfterGitDeletedItsCopyAndTheCopyGoesWithTheWindow() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let request = try sandbox.collected("a.txt", number: 1)
    guard case .diff(let diff) = request else { return }

    _ = try await perform(request, at: sandbox.socketURL).value
    try FileManager.default.removeItem(at: diff.left)

    let controller = await recorder.nextOpened()
    let kept = try #require(controller.collection?.files.first)
    #expect(kept.old.url != diff.left)
    #expect(try String(contentsOf: kept.old.url, encoding: .utf8) == "old a.txt\n")
    #expect(kept.new.url == diff.right)
    controller.window?.close()
    #expect(!FileManager.default.fileExists(atPath: kept.old.url.path))
    await coordinator.finish()
  }

  @Test func copiesOfACrashAreRemovedWhenTheAppStarts() async throws {
    let sandbox = try AppSandbox()
    let left = sandbox.collectionCache.folder.appending(path: "crashed/old/a.txt")
    try FileManager.default.createDirectory(
      at: left.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("old\n".utf8).write(to: left)

    let coordinator = try sandbox.startCoordinator(recorder: WindowRecorder())

    #expect(!FileManager.default.fileExists(atPath: left.path))
    await coordinator.finish()
  }

  /// The folders of `git difftool --dir-diff` and two folders named on the command line open
  /// the window of Compare Folders, which Git waits for.
  ///
  /// Only the folders of Git follow its links into the working tree and name the sides as Git
  /// does.
  @Test(arguments: [true, false])
  func foldersOpenTheWindowOfCompareFoldersAndGitWaitsForIt(isFromGit: Bool) async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let (left, right, tree) = (
      sandbox.folder.appending(path: "left"), sandbox.folder.appending(path: "right"),
      sandbox.folder.appending(path: "repository")
    )
    for (url, text) in [
      (left.appending(path: "a.txt"), "old\n"), (tree.appending(path: "a.txt"), "new\n"),
      (left.appending(path: "same.txt"), "same\n"), (tree.appending(path: "same.txt"), "same\n"),
      (right.appending(path: "new.txt"), "new\n"),
    ] {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(text.utf8).write(to: url)
    }
    for name in ["a.txt", "same.txt"] {
      try FileManager.default.createSymbolicLink(
        at: right.appending(path: name), withDestinationURL: tree.appending(path: name))
    }
    let outcome = perform(
      .folders(.init(left: left, right: right, repository: tree, isFromGit: isFromGit)),
      at: sandbox.socketURL)

    let controller = await recorder.nextOpened()
    let window = try #require(controller.window)
    #expect(controller.collection?.folders == FolderPair(left: left, right: right))
    // The comparison goes on after the window opened, for a few seconds at most. The identical
    // file of Git is not listed, and the window keeps the file it showed first.
    let listed = isFromGit ? 2 : 3
    let deadline = ContinuousClock.now + .seconds(10)
    while !window.subtitle.contains(" of \(listed)"), ContinuousClock.now < deadline {
      await Task.yield()
    }

    #expect(window.subtitle.contains(" of \(listed)"), "\(window.subtitle)")
    #expect(controller.collection?.files.map(\.path) == ["a.txt", "new.txt", "same.txt"])
    #expect(window.subtitle.contains("left ↔ right") == !isFromGit)
    // Git's link to the same file of the working tree holds the same bytes; the user's link is
    // compared by its target.
    #expect(
      controller.collection?.files.last?.change == (isFromGit ? .identical : .modified))
    window.close()

    #expect(try await outcome.value == .closed(.saved))
    await coordinator.finish()
  }
}

extension AppSandbox {
  /// A comparison of file `number` of three that Git hands over from a run in `repository`,
  /// whose earlier side is a temporary copy outside the working tree and whose later side is in
  /// it.
  func collected(
    _ path: String, number: Int, repository: String? = nil
  ) throws -> SessionRequest {
    let tree = folder.appending(path: "repository", directoryHint: .isDirectory)
    let temporary = folder.appending(path: "tmp/\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let left = temporary.appending(path: path)
    let right = tree.appending(path: path)
    try Data("old \(path)\n".utf8).write(to: left)
    try Data("new \(path)\n".utf8).write(to: right)
    return .diff(
      .init(
        left: left, right: right, displayPath: path,
        context: .init(rightRole: .workingCopy, filePosition: .init(number: number, count: 3)),
        origin: .init(repository: repository ?? tree.path(percentEncoded: false), run: nil)))
  }
}
