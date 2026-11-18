import AppKit
import MergeEngine
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// One measurement of a large case: its files on disk, the window that opened them as the app
/// opens them, and the measuring of what the user waits for, each time until the window is laid
/// out and drawn again.
///
/// Every action is measured twice: until the window is laid out, which earlier measurements of
/// the same cases compare with, and once more with a picture of the whole window, which the
/// metric names with `-drawn`. Drawing goes into a bitmap without a screen, so it is an upper bound for
/// the frame that the screen shows.
@MainActor
final class LargeFileRun {
  /// How often to repeat an action: up to `most` times, and while the samples together take
  /// less than `budget`, at least once.
  struct Repetitions {
    var most: Int
    var budget: Duration

    /// Whether the first sample counts apart from the others, which then go by the name of the
    /// metric with `-repeated`: the first time an action happens it often takes longer, as
    /// TextKit lays out what it had not laid out before, and that time is what the user waits
    /// for once.
    var countsTheFirstApart = false

    /// Once only, for an action that can only happen once.
    static let once = Repetitions(most: 1, budget: .zero)

    /// As often as is needed for a steady median of small steps, unless they take long.
    static let steps = Repetitions(most: 21, budget: .seconds(5))

    /// A few times, for an action that takes long even when it is fast; the first time apart.
    static let few = Repetitions(most: 5, budget: .seconds(2), countsTheFirstApart: true)

    /// Whether to take another sample after `count` that took `spent` together.
    func continues(after count: Int, spent: Duration) -> Bool {
      count < most && (count == 0 || spent < budget)
    }

    /// The name of sample `index` of `metric`.
    func name(of metric: String, sample index: Int) -> String {
      countsTheFirstApart && index > 0 ? "\(metric)-repeated" : metric
    }
  }

  let largeCase: LargeFileCase
  let recorder: LargeFileRecorder
  let clock = ContinuousClock()
  let controller: SessionWindowController
  let window: NSWindow
  let contentView: NSView
  private let picture: NSBitmapImageRep
  private let folder: URL

  /// Writes the files of `largeCase`, opens them and measures each step of the way to the first
  /// picture of the window.
  init(_ largeCase: LargeFileCase, recorder: LargeFileRecorder) async throws {
    self.largeCase = largeCase
    self.recorder = recorder
    folder = Self.newFolder()
    let files = try Self.writeFiles(of: largeCase, into: folder)
    let size = try FileManager.default.attributesOfItem(atPath: files.b.path)[.size] as? Int
    recorder.record("size", Double(size ?? 0) / 1_048_576, unit: "MB")
    try await Self.openAndCloseASmallWindow()
    recorder.recordMemory(after: "start")
    try Self.measureTheEngine(on: files, recorder: recorder)

    let clock = ContinuousClock()
    let label = "file.\(largeCase.fileExtension)"
    var sources: (base: SourceFile?, a: SourceFile, b: SourceFile)?
    let read = try clock.measure {
      sources = (
        try files.base.map { try SourceFile(contentsOf: $0, label: label) },
        try SourceFile(contentsOf: files.a, label: label),
        try SourceFile(contentsOf: files.b, label: label)
      )
    }
    recorder.record("read", read)
    let loaded = try #require(sources)
    let comparing = clock.now
    let session =
      largeCase.isMerge
      ? try await Session.merge(
        base: loaded.base, a: loaded.a, b: loaded.b,
        options: ComparisonOptions(mode: .windowDefault))
      : try await Session.diff(old: loaded.a, new: loaded.b, mode: .windowDefault)
    let compared = clock.now - comparing
    recorder.record("session-diff", compared)
    recorder.record(
      "changed-blocks", Double(session.blocks.count { $0.kind != .unchanged }), unit: "blocks")

    var opened: SessionWindowController?
    let opening = try clock.measure { opened = try Windows.controller(for: session) }
    recorder.record("window", opening)
    controller = try #require(opened)
    window = try #require(controller.window)
    contentView = try #require(window.contentView)
    picture = try #require(contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds))
    let drawing = clock.measure { [contentView, picture] in
      contentView.cacheDisplay(in: contentView.bounds, to: picture)
    }
    recorder.record("first-draw", drawing)
    recorder.record("time-to-display", read + compared + opening + drawing)
    recorder.recordMemory(after: "open")
  }

  isolated deinit {
    window.close()
    do {
      try FileManager.default.removeItem(at: folder)
    } catch {
      Issue.record(error, "The files of the measurement stay in \(folder.path)")
    }
  }

  /// Writes the files of `largeCase` into `folder`, which it creates.
  ///
  /// - Returns: Where the base, if any, A and B are, or for a comparison the older and the newer
  ///   file as A and B.
  static func writeFiles(
    of largeCase: LargeFileCase, into folder: URL
  ) throws -> (base: URL?, a: URL, b: URL) {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let texts = largeCase.texts()
    let names =
      largeCase.isMerge ? ("base", "theirs", "ours") : ("base", "old", "new")
    func write(_ text: String, as name: String) throws -> URL {
      let url = folder.appending(path: "\(name).\(largeCase.fileExtension)")
      try Data(text.utf8).write(to: url)
      return url
    }
    return (
      try texts.base.map { try write($0, as: names.0) }, try write(texts.a, as: names.1),
      try write(texts.b, as: names.2)
    )
  }

  /// Opens a small comparison and draws it once, so that what the first window of a process
  /// costs once (fonts, menus, the classes of AppKit) does not count against the large one.
  private static func openAndCloseASmallWindow() async throws {
    let session = try await SampleDiffs.diff(old: "a\nb\n", new: "a\nc\n")
    let controller = try Windows.controller(for: session)
    let window = try #require(controller.window)
    let contentView = try #require(window.contentView)
    let picture = try #require(contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds))
    contentView.cacheDisplay(in: contentView.bounds, to: picture)
    window.close()
  }

  /// A new folder for the files of a measurement, beside the output, where the script removes it
  /// also after a run it stopped.
  private static func newFolder() -> URL {
    let output = ProcessInfo.processInfo.environment["SEAMERGE_MEASURE_OUTPUT"].map {
      URL(filePath: $0).deletingLastPathComponent()
    }
    return (output ?? FileManager.default.temporaryDirectory)
      .appending(path: "SeamergeMeasurements-\(UUID().uuidString)", directoryHint: .isDirectory)
  }

  /// Writes the files of `largeCase`, opens them as the app opens them and measures how long the
  /// user waits for the window with its headers and for the lines in it, each until the window
  /// is laid out and drawn, the longest hold of the main actor meanwhile, and the memory after.
  ///
  /// A comparison that is ready soon opens the window with its lines, in its first picture; then
  /// both times are the same. Meant for a process of its own, so that the other measurements of
  /// the case open their files as the first time.
  static func measureOpening(of largeCase: LargeFileCase, recorder: LargeFileRecorder)
    async throws
  {
    let folder = newFolder()
    defer {
      do {
        try FileManager.default.removeItem(at: folder)
      } catch {
        Issue.record(error, "The files of the measurement stay in \(folder.path)")
      }
    }
    let files = try writeFiles(of: largeCase, into: folder)
    try await openAndCloseASmallWindow()
    let label = "file.\(largeCase.fileExtension)"
    let file = { (url: URL) in SessionFile(url: url, label: label) }
    let clock = ContinuousClock()
    let start = clock.now
    var headers = Duration.zero
    var lines = Duration.zero
    var opened: SessionWindowController?
    // The times are taken within the work: once it is over, the main actor may first color the
    // syntax, which comes after the first picture.
    let held = try await longestHold {
      let controller =
        largeCase.isMerge
        ? try await SessionWindowController.openMerge(
          base: files.base.map(file), a: file(files.a), b: file(files.b), mode: .windowDefault,
          context: SessionContext(), undoManager: UndoManager(), settings: .private())
        : try await SessionWindowController.openDiff(
          old: file(files.a), new: file(files.b), mode: .windowDefault,
          context: SessionContext(), undoManager: UndoManager(), settings: .private())
      opened = controller
      let window = try #require(controller.window)
      let contentView = try #require(window.contentView)
      let picture = try #require(
        contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds))
      let waits = controller.waitsForComparison
      // The app draws a new window in the pass of the run loop after the one that made it, so
      // the main actor is let go here as there, and the making and the first picture are held
      // apart.
      await Task.yield()
      contentView.layoutSubtreeIfNeeded()
      contentView.cacheDisplay(in: contentView.bounds, to: picture)
      headers = clock.now - start
      lines = headers
      // A window that came filled showed its lines in that first picture.
      guard waits else { return }
      await controller.comparisonFill?.value
      contentView.layoutSubtreeIfNeeded()
      contentView.cacheDisplay(in: contentView.bounds, to: picture)
      lines = clock.now - start
    }
    recorder.record("open-headers-drawn", headers)
    recorder.record("open-lines-drawn", lines)
    recorder.record("open-longest-hold", held)
    recorder.recordMemory(after: "opening")
    opened?.window?.close()
  }

  /// Measures the engine alone on the files, for its share of the comparison, in the mode a
  /// window starts in.
  private static func measureTheEngine(
    on files: (base: URL?, a: URL, b: URL), recorder: LargeFileRecorder
  ) throws {
    let a = try Data(contentsOf: files.a)
    let b = try Data(contentsOf: files.b)
    let base = try files.base.map { try Data(contentsOf: $0) }
    let clock = ContinuousClock()
    for _ in 0..<3 {
      let duration = try clock.measure {
        if let base {
          _ = try MergeEngine.Merge(base: base, a: a, b: b, whitespace: .ignoreAmount)
        } else {
          _ = try MergeEngine.Diff(a, b, whitespace: .ignoreAmount)
        }
      }
      recorder.record("engine-diff", duration)
    }
  }

  /// Carries out `action` as often as `repetitions` allow, each time after `prepare`, and
  /// records how long it takes until the window is laid out, as `metric`, and until it is drawn
  /// as well, as `metric-drawn`.
  func measure(
    _ metric: String, _ repetitions: Repetitions, prepare: () -> Void = {},
    action: () -> Void
  ) {
    var spent = Duration.zero
    var count = 0
    while repetitions.continues(after: count, spent: spent) {
      let (laidOut, drawn) = asOneEvent {
        prepare()
        contentView.layoutSubtreeIfNeeded()
        let laidOut = clock.measure {
          action()
          contentView.layoutSubtreeIfNeeded()
        }
        return (laidOut, clock.measure { draw() })
      }
      let name = repetitions.name(of: metric, sample: count)
      recorder.record(name, laidOut)
      recorder.record("\(name)-drawn", laidOut + drawn)
      spent += laidOut + drawn
      count += 1
    }
  }

  /// Carries out `body` as the run loop handles an event: what it leaves to the autorelease
  /// pool is released afterwards.
  ///
  /// The measurement runs in one long task on the main actor, whose pool would otherwise keep
  /// everything that every step left to it, such as the views and fragments of text replaced
  /// or scrolled out of view, until the end; the memory would grow with each step as it never
  /// does in the app.
  func asOneEvent<Result>(_ body: () throws -> Result) rethrows -> Result {
    try autoreleasepool(invoking: body)
  }

  /// Draws the whole window into a bitmap, as the screen would show it.
  func draw() {
    contentView.cacheDisplay(in: contentView.bounds, to: picture)
  }

  /// Measures `count` scroll steps of `step` points each in the pane of B, from 40 % of its
  /// height on: the layout, the picture of the pane, their sum as one frame of the pane, and the
  /// layout with the picture of the whole window.
  func scroll(_ label: String, step: (_ visibleHeight: CGFloat) -> CGFloat, count: Int) throws {
    let pane = try #require(controller.layout.sourcePane(.b))
    let textView = pane.documentView
    let scrollView = try #require(textView.enclosingScrollView)
    let clip = scrollView.contentView
    let panePicture = try #require(pane.bitmapImageRepForCachingDisplay(in: pane.bounds))
    var y = max(0, textView.frame.height * 0.4)
    for _ in 0..<count {
      y = min(y + step(clip.bounds.height), max(0, textView.frame.height - clip.bounds.height))
      let target = y
      let (laidOut, windowDrawn, paneDrawn) = asOneEvent {
        let laidOut = clock.measure {
          clip.scroll(to: NSPoint(x: 0, y: target))
          scrollView.reflectScrolledClipView(clip)
          contentView.layoutSubtreeIfNeeded()
        }
        let windowDrawn = clock.measure { draw() }
        return (
          laidOut, windowDrawn,
          clock.measure { pane.cacheDisplay(in: pane.bounds, to: panePicture) }
        )
      }
      recorder.record("scroll-\(label)-layout", laidOut)
      recorder.record("scroll-\(label)-panedraw", paneDrawn)
      recorder.record("scroll-\(label)-step", laidOut + paneDrawn)
      recorder.record("scroll-\(label)-draw", laidOut + windowDrawn)
    }
  }

  /// Carries out `body` as `phase` and records the memory after it.
  func phase(_ phase: String, _ body: () async throws -> Void) async rethrows {
    recorder.begin(phase)
    try await body()
    recorder.recordMemory(after: phase)
  }

  /// Lets the run loop handle what is due, for `duration`, as while the user pauses before the
  /// next action: work the window does in the background ends or comes to rest.
  func pause(_ duration: Duration = .milliseconds(500)) {
    let end = clock.now + duration
    while clock.now < end {
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
    }
  }

  /// Carries out `work` and returns the longest time the main actor was held at a stretch
  /// meanwhile, so that the user could not interact.
  ///
  /// A task beside it asks for the main actor every millisecond and measures how long it waits.
  func longestHold(during work: () async throws -> Void) async rethrows -> Duration {
    try await Self.longestHold(during: work)
  }

  /// Carries out `work` and returns the longest time the main actor was held at a stretch
  /// meanwhile, as ``longestHold(during:)`` does.
  static func longestHold(during work: () async throws -> Void) async rethrows -> Duration {
    let watch = Task.detached(priority: .userInitiated) { () -> Duration in
      let clock = ContinuousClock()
      var longest = Duration.zero
      while !Task.isCancelled {
        let asked = clock.now
        await MainActor.run {}
        longest = max(longest, clock.now - asked)
        do {
          try await clock.sleep(for: .milliseconds(1))
        } catch {
          break
        }
      }
      return longest
    }
    defer { watch.cancel() }
    try await work()
    watch.cancel()
    return await watch.value
  }
}
