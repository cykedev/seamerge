// A library that the scripts load into a copy of the app, never into the app as shipped, to see
// and drive a comparison without the permissions for recording the screen or controlling the
// computer: it presses the default button of the sheet the files fill, gives the window of the
// comparison a size, an appearance and a scroll position, and then draws the window into a PNG
// while every window stays transparent, or shows it without activating the app, counts its
// frames and scrolls it with flicks as a trackpad does, through events it posts to the copy.
// It turns away the requests of the app to come to the front, and should the copy come to the
// front all the same, it ends it with a line that says so.
//
// Built with -Xlinker -init -Xlinker _seamergeProbeStart, so that dyld starts it before the app
// runs. It reads what to do from the environment, SEAMERGE_PROBE_ and more, and takes itself and
// those variables out of the environment, so that the processes the copy starts do not load it.
// Every line it writes goes to SEAMERGE_PROBE_OUTPUT; without that variable it does nothing.

import AppKit
import ObjectiveC
import QuartzCore

/// Starts the probe as dyld loads it.
@_cdecl("seamergeProbeStart")
func seamergeProbeStart() {
  let environment = ProcessInfo.processInfo.environment
  unsetenv("DYLD_INSERT_LIBRARIES")
  for name in environment.keys where name.hasPrefix("SEAMERGE_PROBE_") {
    unsetenv(name)
  }
  guard let task = ProbeTask(environment), let output = fopen(task.outputPath, "w") else { return }
  setvbuf(output, nil, _IOLBF, 0)
  let log = ProbeLog(file: output)
  log.note("probe loaded")
  ProbeWindows.turnTransparent(log: log)
  ProbeActivation.refuse(log: log)
  if task.look.increasesContrast {
    ProbeLook.reportIncreasedContrast()
  }
  // The app is there once it is about to finish launching; the windows come after.
  NotificationCenter.default.addObserver(
    forName: NSApplication.willFinishLaunchingNotification, object: nil, queue: .main
  ) { _ in
    MainActor.assumeIsolated {
      Probe.start(task, log: log)
    }
  }
}

/// The windows of the copy, which nobody at the screen sees unless the probe shows one.
///
/// Every window is fully transparent and lets the mouse through from the moment it is made, and
/// stays so whatever the app or AppKit sets later, however it comes onto a screen: through the
/// initializers of `NSWindow`, which every window, panel and alert goes through, and the setters
/// of its transparency and of the mouse. A titled window cannot stay off the screens instead, as
/// AppKit moves it back onto one when it is ordered in, and the copy shows its windows even when
/// it is launched hidden.
enum ProbeWindows {
  /// The windows the probe shows itself, which may take the transparency the probe gives them.
  @MainActor static var shown: Set<ObjectIdentifier> = []

  /// Makes every window transparent from the moment it is made, for the rest of the process,
  /// noting in `log` each time the app asks a window to be seen.
  static func turnTransparent(log: ProbeLog) {
    replaceInitializers()
    replaceAlphaSetter(log: log)
    replaceMouseSetter()
  }

  /// Has every window made from now on start transparent and let the mouse through.
  ///
  /// An initializer consumes the object it is sent to and returns one it owns, which the
  /// replacements pass on untouched as unmanaged references.
  private static func replaceInitializers() {
    typealias Initializer =
      @convention(c) (Unmanaged<NSWindow>, Selector, NSRect, UInt, UInt, ObjCBool) ->
      Unmanaged<NSWindow>?
    typealias ScreenInitializer =
      @convention(c) (Unmanaged<NSWindow>, Selector, NSRect, UInt, UInt, ObjCBool, NSScreen?) ->
      Unmanaged<NSWindow>?
    let selector = #selector(NSWindow.init(contentRect:styleMask:backing:defer:))
    if let method = class_getInstanceMethod(NSWindow.self, selector) {
      let original = unsafeBitCast(method_getImplementation(method), to: Initializer.self)
      let replacement:
        @convention(block) (Unmanaged<NSWindow>, NSRect, UInt, UInt, ObjCBool) ->
          Unmanaged<NSWindow>? = { window, rect, style, backing, deferred in
            let made = original(window, selector, rect, style, backing, deferred)
            made.map { makeTransparent($0.takeUnretainedValue()) }
            return made
          }
      method_setImplementation(method, imp_implementationWithBlock(replacement))
    }
    let screenSelector = #selector(NSWindow.init(contentRect:styleMask:backing:defer:screen:))
    if let method = class_getInstanceMethod(NSWindow.self, screenSelector) {
      let original = unsafeBitCast(method_getImplementation(method), to: ScreenInitializer.self)
      let replacement:
        @convention(block) (Unmanaged<NSWindow>, NSRect, UInt, UInt, ObjCBool, NSScreen?) ->
          Unmanaged<NSWindow>? = { window, rect, style, backing, deferred, screen in
            let made = original(window, screenSelector, rect, style, backing, deferred, screen)
            made.map { makeTransparent($0.takeUnretainedValue()) }
            return made
          }
      method_setImplementation(method, imp_implementationWithBlock(replacement))
    }
  }

  private static func makeTransparent(_ window: NSWindow) {
    MainActor.assumeIsolated {
      window.alphaValue = 0
      window.ignoresMouseEvents = true
    }
  }

  /// Keeps every window but those the probe shows fully transparent, whatever transparency the
  /// app or AppKit gives it, and notes in `log` each time one is asked to be seen.
  private static func replaceAlphaSetter(log: ProbeLog) {
    typealias Setter = @convention(c) (NSWindow, Selector, CGFloat) -> Void
    let selector = #selector(setter: NSWindow.alphaValue)
    guard let method = class_getInstanceMethod(NSWindow.self, selector) else { return }
    let original = unsafeBitCast(method_getImplementation(method), to: Setter.self)
    let replacement: @convention(block) (NSWindow, CGFloat) -> Void = { window, alpha in
      let (isShown, number) = MainActor.assumeIsolated {
        (shown.contains(ObjectIdentifier(window)), window.windowNumber)
      }
      if !isShown, alpha > 0 {
        log.note("window \(number) asked for alpha \(alpha), stays at 0")
      }
      original(window, selector, isShown ? alpha : 0)
    }
    method_setImplementation(method, imp_implementationWithBlock(replacement))
  }

  /// Has every window let the mouse through to the windows below, whatever the app asks.
  private static func replaceMouseSetter() {
    typealias Setter = @convention(c) (NSWindow, Selector, ObjCBool) -> Void
    let selector = #selector(setter: NSWindow.ignoresMouseEvents)
    guard let method = class_getInstanceMethod(NSWindow.self, selector) else { return }
    let original = unsafeBitCast(method_getImplementation(method), to: Setter.self)
    let replacement: @convention(block) (NSWindow, ObjCBool) -> Void = { window, _ in
      original(window, selector, true)
    }
    method_setImplementation(method, imp_implementationWithBlock(replacement))
  }

  /// Has every window of a comparison draw as the key and main window.
  ///
  /// So the window draws its focus as the window in front does on the screen, with the
  /// insertion point and in the accent color; the copy never becomes active, so no window of it
  /// would otherwise. The buttons of the title bar stay gray, as AppKit draws them in color only
  /// in the active app.
  static func drawComparisonsAsKey() {
    guard let comparison = NSClassFromString("SeamergeUI.SessionWindow") else { return }
    let selectors = [
      #selector(getter: NSWindow.isKeyWindow), #selector(getter: NSWindow.isMainWindow),
    ]
    for selector in selectors {
      guard let method = class_getInstanceMethod(NSWindow.self, selector) else { continue }
      let isKey: @convention(block) (AnyObject) -> Bool = { _ in true }
      class_replaceMethod(
        comparison, selector, imp_implementationWithBlock(isKey), method_getTypeEncoding(method))
    }
  }
}

/// Keeps the copy from coming to the front, which would take the key focus from the person at
/// the screen, and stops it should it come to the front all the same.
///
/// The probe never asks for it and the copy launches in the background, but AppKit asks on its
/// own as it opens the files the copy was launched with.
enum ProbeActivation {
  /// Turns away every request of the app to come to the front, noting it in `log`, and has the
  /// app becoming active by any other way end the process with a line in `log`.
  static func refuse(log: ProbeLog) {
    let selectors = [
      #selector(NSApplication.activate(ignoringOtherApps:)),
      #selector(NSApplication.activate as (NSApplication) -> () -> Void),
    ]
    for selector in selectors {
      guard let method = class_getInstanceMethod(NSApplication.self, selector) else { continue }
      let refuse: @convention(block) (AnyObject) -> Void = { _ in
        log.note("turned away a request to come to the front")
      }
      method_setImplementation(method, imp_implementationWithBlock(refuse))
    }
    NotificationCenter.default.addObserver(
      forName: NSApplication.willBecomeActiveNotification, object: nil, queue: nil
    ) { _ in
      log.note("failed: the app became active")
      exit(1)
    }
  }
}

/// What the probe is to do, as the environment of the copy says.
struct ProbeTask: Sendable {
  /// What becomes of the comparison once it shows.
  enum Goal: Sendable {
    /// Draw the window into a PNG at this path, without showing it.
    case picture(path: String)

    /// Show the window on the screen with the lowest frame rate, or the highest one if `fast`,
    /// fully transparent if `transparent`, count its frames if `counts`, and play `count` flicks
    /// down and as many up a second after a file appears at `go`.
    case flicks(count: Int, fast: Bool, transparent: Bool, counts: Bool, go: String)
  }

  /// The file the probe writes its lines to.
  var outputPath: String

  /// What becomes of the comparison.
  var goal: Goal

  /// The appearance of the app.
  var look: ProbeLook

  /// The size of the content of the window: `nil` keeps the size the app gives it, zero takes
  /// its least size.
  var contentSize: CGSize?

  /// Where the larger pane is scrolled to before anything else, as a fraction of how far it can
  /// scroll; `nil` leaves it where the window opens.
  var scrollFraction: Double?

  /// How long the window may settle after it is laid out, before it is drawn or scrolled.
  var settleTime: TimeInterval

  /// Reads the task from `environment`, or gives `nil` if it names no output or no goal.
  init?(_ environment: [String: String]) {
    guard let outputPath = environment["SEAMERGE_PROBE_OUTPUT"] else { return nil }
    self.outputPath = outputPath
    if let path = environment["SEAMERGE_PROBE_PICTURE"] {
      goal = .picture(path: path)
    } else if let flicks = environment["SEAMERGE_PROBE_FLICKS"].flatMap(Int.init), flicks > 0 {
      goal = .flicks(
        count: flicks, fast: environment["SEAMERGE_PROBE_SCREEN"] == "fast",
        transparent: environment["SEAMERGE_PROBE_TRANSPARENT"] == "1",
        counts: environment["SEAMERGE_PROBE_COUNT_FRAMES"] != "0",
        go: environment["SEAMERGE_PROBE_GO"] ?? "")
    } else {
      return nil
    }
    look = ProbeLook(name: environment["SEAMERGE_PROBE_APPEARANCE"] ?? "light")
    switch environment["SEAMERGE_PROBE_SIZE"] {
    case nil, "": contentSize = nil
    case "min": contentSize = .zero
    case let size?:
      let parts = size.split(separator: "x").compactMap { Double($0) }
      contentSize = parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
    }
    scrollFraction = environment["SEAMERGE_PROBE_SCROLL"].flatMap(Double.init)
    settleTime = environment["SEAMERGE_PROBE_SETTLE"].flatMap(Double.init) ?? 1
  }
}

/// An appearance of the app, with or without increased contrast.
struct ProbeLook: Sendable {
  /// Whether the appearance is dark.
  var isDark: Bool

  /// Whether the app is told that the system increases contrast.
  var increasesContrast: Bool

  /// The look named `name`: light or dark, followed by -increased-contrast for that.
  init(name: String) {
    isDark = name.hasPrefix("dark")
    increasesContrast = name.hasSuffix("-increased-contrast")
  }

  /// Makes `NSWorkspace` report that the system increases contrast, so that the window gives
  /// its own colors their values for it; system colors keep theirs, since an appearance with
  /// increased contrast cannot be made by name.
  static func reportIncreasedContrast() {
    let selector = #selector(getter: NSWorkspace.accessibilityDisplayShouldIncreaseContrast)
    guard let method = class_getInstanceMethod(NSWorkspace.self, selector) else { return }
    let increases: @convention(block) (AnyObject) -> Bool = { _ in true }
    method_setImplementation(method, imp_implementationWithBlock(increases))
  }
}

/// The lines of the probe, each with the time of the media clock first; safe from any thread.
struct ProbeLog: @unchecked Sendable {
  /// The open file, line-buffered; `fputs` locks it for each line.
  let file: UnsafeMutablePointer<FILE>

  /// Writes `line` as it is.
  func write(_ line: String) {
    fputs(line + "\n", file)
  }

  /// Writes `message` after the time of the media clock.
  func note(_ message: String) {
    write(String(format: "%.6f ", CACurrentMediaTime()) + message)
  }
}

/// Opens the comparison, prepares its window and draws or scrolls it.
@MainActor
final class Probe: NSObject {
  /// The probe of the process, once the app is about to finish launching.
  private static var current: Probe?

  private let task: ProbeTask
  private let log: ProbeLog
  private var poll: Timer?
  private var scrolledSpan: ClosedRange<CGFloat>?
  private var isLiveScrolling = false
  private var liveScrollEnd: CFTimeInterval = 0
  private var pressedSheet = false
  private var window: NSWindow?
  private var link: CADisplayLink?
  private var screenWatch: ProbeScreenWatch?
  private let started = CACurrentMediaTime()

  /// How long the comparison may take to open, as for the largest files the measurements use.
  private static let openingTimeLimit: TimeInterval = 600

  /// Starts `task`, writing to `log`.
  static func start(_ task: ProbeTask, log: ProbeLog) {
    let probe = Probe(task: task, log: log)
    current = probe
    probe.begin()
  }

  private init(task: ProbeTask, log: ProbeLog) {
    self.task = task
    self.log = log
  }

  private func begin() {
    NSApp.appearance = NSAppearance(named: task.look.isDark ? .darkAqua : .aqua)
    log.note(
      "probe started, appearance \(task.look.isDark ? "dark" : "light")"
        + (task.look.increasesContrast ? " with increased contrast" : "")
        + ", may post events to the system \(CGPreflightPostEventAccess())"
        + ", may record the screen \(CGPreflightScreenCaptureAccess())")
    // Until the window is drawn or shown, before anything is measured.
    screenWatch = ProbeScreenWatch(log: log)
    if case .picture = task.goal {
      ProbeWindows.drawComparisonsAsKey()
    }
    watchActivation()
    poll = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
      MainActor.assumeIsolated {
        Probe.current?.step()
      }
    }
  }

  /// Notes every time a window becomes key in the copy, which stays in the background, or
  /// becomes visible or hidden on a screen as far as AppKit knows.
  private func watchActivation() {
    let center = NotificationCenter.default
    center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) {
      [log] _ in
      log.note("a window became key")
    }
    center.addObserver(
      self, selector: #selector(windowDidChangeOcclusionState(_:)),
      name: NSWindow.didChangeOcclusionStateNotification, object: nil)
  }

  @objc private func windowDidChangeOcclusionState(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    let visible = window.occlusionState.contains(.visible)
    log.note("window \(window.windowNumber) \(visible ? "visible" : "hidden") on a screen")
  }

  /// Takes the next step on the way to the comparison: presses the default button of the sheet
  /// the files fill, then waits until the window of the comparison has its lines.
  private func step() {
    if !pressedSheet,
      let sheet = NSApp.windows.first(where: { $0.isSheet && $0.defaultButtonCell != nil }),
      let button = sheet.defaultButtonCell, button.isEnabled
    {
      pressedSheet = true
      log.note("pressing \(button.title ?? "the default button") in the sheet \(sheet.title)")
      button.performClick(nil)
      return
    }
    guard let window = NSApp.windows.first(where: Self.isComparison), Self.hasItsLines(window)
    else {
      if CACurrentMediaTime() - started > Self.openingTimeLimit {
        fail("no comparison opened within \(Int(Self.openingTimeLimit)) s")
      }
      return
    }
    poll?.invalidate()
    poll = nil
    self.window = window
    log.note("comparison open: \(window.title)")
    prepare(window)
    if let fraction = task.scrollFraction {
      // Once the window has its colors, as the user scrolls a window that shows.
      Timer.scheduledTimer(withTimeInterval: task.settleTime / 2, repeats: false) { _ in
        MainActor.assumeIsolated {
          guard let window = Probe.current?.window else { return }
          Probe.current?.scroll(window, to: fraction)
        }
      }
    }
    Timer.scheduledTimer(withTimeInterval: task.settleTime, repeats: false) { _ in
      MainActor.assumeIsolated {
        Probe.current?.finish()
      }
    }
  }

  /// Whether `window` shows a comparison or a merge.
  private static func isComparison(_ window: NSWindow) -> Bool {
    NSStringFromClass(type(of: window)).hasSuffix(".SessionWindow")
  }

  /// Whether the panes of `window` have their lines, rather than waiting for the comparison with
  /// a placeholder.
  private static func hasItsLines(_ window: NSWindow) -> Bool {
    guard let content = window.contentView else { return false }
    let views = descendants(of: content)
    return !views.isEmpty && !views.contains { $0.accessibilityPlaceholderValue() != nil }
  }

  /// Gives `window` its size.
  private func prepare(_ window: NSWindow) {
    if let size = task.contentSize {
      let least = window.contentMinSize
      window.setContentSize(
        CGSize(width: max(size.width, least.width), height: max(size.height, least.height)))
    }
    window.contentView?.layoutSubtreeIfNeeded()
    let size = window.contentView?.bounds.size ?? .zero
    log.note(
      String(format: "window content %.0f x %.0f points", size.width, size.height)
        + ", scale \(window.backingScaleFactor), screen \(window.screen?.localizedName ?? "none")")
  }

  /// Scrolls the larger pane of `window` to the fraction of the task, through the scroll wheel,
  /// so that the other panes follow as they follow the user.
  private func scroll(_ window: NSWindow, to fraction: Double) {
    guard let pane = Self.largestPane(in: window), let document = pane.documentView else { return }
    let range = max(document.frame.height - pane.contentView.bounds.height, 0)
    let distance = min(max(fraction, 0), 1) * range - pane.contentView.bounds.minY
    if let event = ProbeEvents.scroll(
      delta: -distance, phase: 0, momentum: 0, window: window.windowNumber,
      at: Self.center(of: pane, in: window))
    {
      NSApp.postEvent(event, atStart: false)
    }
    log.note(String(format: "scrolling the larger pane by %.0f points", distance))
  }

  /// Draws the window or plays the flicks, once it has settled.
  private func finish() {
    guard let window else { return }
    switch task.goal {
    case .picture(let path):
      drawPicture(of: window, to: path)
      screenWatch?.stop()
      log.note("done")
    case .flicks(let count, let fast, let transparent, let counts, let go):
      show(window, fast: fast, transparent: transparent)
      if counts {
        countFrames(of: window)
      }
      poll = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
        MainActor.assumeIsolated {
          Probe.current?.playFlicks(count, onceThereIs: go)
        }
      }
    }
  }

  // MARK: - Picture

  /// Draws the whole window, title bar and toolbar included, at the backing scale into a PNG at
  /// `path`, as the pictures of the tests are drawn: the frame view caches its display.
  private func drawPicture(of window: NSWindow, to path: String) {
    // In sRGB, as in the tests, whose pictures are compared with these: a window that no
    // screen gives a color space blends in a linear one, which makes translucent fills lighter.
    window.colorSpace = .sRGB
    guard let frameView = window.contentView?.superview else {
      return fail("the window has no frame view")
    }
    frameView.layoutSubtreeIfNeeded()
    Self.orderToolbarGlass(in: frameView)
    guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
      return fail("the window cannot be drawn")
    }
    frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]),
      FileManager.default.createFile(atPath: path, contents: data)
    else {
      return fail("cannot write \(path)")
    }
    log.note("picture \(bitmap.pixelsWide) x \(bitmap.pixelsHigh) pixels: \(path)")
  }

  /// Puts the glass behind the items of the toolbar in order from left to right, so that the
  /// same window draws the same picture each time, as the tests do.
  private static func orderToolbarGlass(in frameView: NSView) {
    let glass = descendants(of: frameView).filter { $0 is NSGlassEffectView }
    let pieces = Set(glass.compactMap(\.superview).map(ObjectIdentifier.init))
    let groups = Set(glass.compactMap(\.superview?.superview))
    for group in groups
    where group.subviews.count > 1
      && group.subviews.allSatisfy({ pieces.contains(ObjectIdentifier($0)) })
    {
      group.sortSubviews(
        { first, second, _ in
          if first.frame.minX == second.frame.minX { return .orderedSame }
          return first.frame.minX < second.frame.minX ? .orderedAscending : .orderedDescending
        }, context: nil)
    }
  }

  // MARK: - Flicks

  /// Moves `window` to the top left of the screen with the lowest frame rate, or the highest if
  /// `fast`, and shows it there above other windows, without activating the app or taking the
  /// key focus, and letting the pointer through to the windows below; fully transparent if
  /// `transparent`.
  private func show(_ window: NSWindow, fast: Bool, transparent: Bool) {
    let screens = NSScreen.screens.sorted {
      $0.maximumFramesPerSecond < $1.maximumFramesPerSecond
    }
    guard let screen = fast ? screens.last : screens.first else { return fail("no screen") }
    let visible = screen.visibleFrame
    window.setFrameTopLeftPoint(CGPoint(x: visible.minX + 20, y: visible.maxY - 20))
    window.level = .floating
    screenWatch?.stop()
    ProbeWindows.shown.insert(ObjectIdentifier(window))
    window.alphaValue = transparent ? 0 : 1
    NotificationCenter.default.addObserver(
      self, selector: #selector(windowDidChangeScreen(_:)),
      name: NSWindow.didChangeScreenNotification, object: window)
    NSApp.unhideWithoutActivation()
    window.orderFrontRegardless()
    log.note(
      "showing the window on \(screen.localizedName) at \(screen.maximumFramesPerSecond) Hz"
        + (transparent ? ", transparent" : "") + ", app active \(NSApp.isActive)")
  }

  @objc private func windowDidChangeScreen(_ notification: Notification) {
    guard let window, link != nil else { return }
    countFrames(of: window)
  }

  /// Writes a line for each frame of `window`.
  ///
  /// Each time the display link of its content view fires, the line has the time of the frame,
  /// the time of the next one and the time now. A frame the main thread is too busy for never
  /// fires.
  private func countFrames(of window: NSWindow) {
    guard let content = window.contentView else { return }
    link?.invalidate()
    let link = content.displayLink(target: self, selector: #selector(frame(_:)))
    // On a screen whose rate varies, as with ProMotion, the link asks for the highest one, which
    // scrolling gets from the system anyway; otherwise it would count at 60 Hz.
    let highest = Float(window.screen?.maximumFramesPerSecond ?? 60)
    link.preferredFrameRateRange = CAFrameRateRange(
      minimum: highest, maximum: highest, preferred: highest)
    link.add(to: .main, forMode: .common)
    self.link = link
    log.write("# window \(window.title)")
  }

  @objc private func frame(_ link: CADisplayLink) {
    log.write(
      String(
        format: "%.6f %.6f %.6f", link.timestamp, link.targetTimestamp, CACurrentMediaTime()))
  }

  /// Plays `count` flicks down and as many up a second after a file appears at `go`, or at once
  /// if `go` is empty.
  private func playFlicks(_ count: Int, onceThereIs go: String) {
    guard go.isEmpty || FileManager.default.fileExists(atPath: go) else { return }
    poll?.invalidate()
    poll = nil
    // A second for the frames to settle, and for whatever measures them to start.
    Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
      MainActor.assumeIsolated {
        Probe.current?.playFlicks(count)
      }
    }
  }

  /// Plays `count` flicks down and as many up over the larger pane, on a thread of their own,
  /// then writes when they began and ended and the frame rate of the screen.
  private func playFlicks(_ count: Int) {
    guard let window, let pane = Self.largestPane(in: window) else {
      return fail("the window has no pane to scroll")
    }
    let flicks = ProbeFlicks(
      window: window.windowNumber, point: Self.center(of: pane, in: window), count: count)
    let rate = window.screen?.maximumFramesPerSecond ?? 60
    let queue = ProbeEventQueue(application: NSApp)
    scrolledSpan = pane.contentView.bounds.minY...pane.contentView.bounds.minY
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(paneDidScroll(_:)), name: NSView.boundsDidChangeNotification,
      object: pane.contentView)
    center.addObserver(
      self, selector: #selector(liveScrollDidStart(_:)),
      name: NSScrollView.willStartLiveScrollNotification, object: pane)
    center.addObserver(
      self, selector: #selector(liveScrollDidEnd(_:)),
      name: NSScrollView.didEndLiveScrollNotification, object: pane)
    Thread.detachNewThread {
      let (start, posted) = flicks.play(into: queue)
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          Probe.current?.endFlicks(startedAt: start, postedUntil: posted, rate: rate)
        }
      }
    }
  }

  @objc private func liveScrollDidStart(_ notification: Notification) {
    isLiveScrolling = true
  }

  @objc private func liveScrollDidEnd(_ notification: Notification) {
    isLiveScrolling = false
    liveScrollEnd = CACurrentMediaTime()
  }

  /// Keeps how far the pane scrolled during the flicks.
  @objc private func paneDidScroll(_ notification: Notification) {
    guard let clip = notification.object as? NSClipView, let span = scrolledSpan else { return }
    let offset = clip.bounds.minY
    scrolledSpan = min(span.lowerBound, offset)...max(span.upperBound, offset)
  }

  /// Writes when the flicks began and ended and the frame rate of the screen, once the glide
  /// that AppKit adds after the last event has come to rest, at most three seconds after it:
  /// the flicks end with the later of the last event and the end of the glide.
  private func endFlicks(
    startedAt start: CFTimeInterval, postedUntil posted: CFTimeInterval, rate: Int
  ) {
    guard !isLiveScrolling || CACurrentMediaTime() - posted > 3 else {
      Timer.scheduledTimer(withTimeInterval: 0.02, repeats: false) { _ in
        MainActor.assumeIsolated {
          Probe.current?.endFlicks(startedAt: start, postedUntil: posted, rate: rate)
        }
      }
      return
    }
    let end = max(posted, liveScrollEnd)
    log.write("flicks \(start) \(end) \(rate)")
    log.note(
      String(format: "the last glide ended %.0f ms after the last event", (end - posted) * 1000))
    if let span = scrolledSpan {
      log.note(
        String(
          format: "the pane scrolled between %.0f and %.0f points", span.lowerBound, span.upperBound
        ))
    }
    log.note("done")
  }

  // MARK: - Views

  /// The scroll view of the pane that takes the most room in `window`, the one the user would
  /// scroll.
  private static func largestPane(in window: NSWindow) -> NSScrollView? {
    guard let content = window.contentView else { return nil }
    return descendants(of: content).compactMap { $0 as? NSScrollView }
      .filter { !$0.isHiddenOrHasHiddenAncestor && $0.documentView is NSTextView }
      .max { area(of: $0) < area(of: $1) }
  }

  private static func area(of view: NSView) -> CGFloat {
    view.visibleRect.width * view.visibleRect.height
  }

  /// The middle of `view` in the coordinates of `window`.
  private static func center(of view: NSView, in window: NSWindow) -> CGPoint {
    let frame = view.convert(view.bounds, to: nil)
    return CGPoint(x: frame.midX, y: frame.midY)
  }

  private static func descendants(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(descendants(of:))
  }

  /// Writes why the probe stops, and stops the copy.
  private func fail(_ message: String) {
    log.note("failed: \(message)")
    exit(1)
  }
}

/// Watches whether a window of the process comes onto a screen, through the list of windows
/// that the window server keeps, which tells every process about its own windows without the
/// permission to record the screen.
final class ProbeScreenWatch: @unchecked Sendable {
  private let queue = DispatchQueue(label: "app.eiden.seamerge.probe.screen")
  private let timer: DispatchSourceTimer
  private let log: ProbeLog
  // Used on the queue only.
  private var known: [Int: String] = [:]
  private var checks = 0
  private var stopped = false

  /// Starts watching, every 20 milliseconds, writing to `log` each window of the process the
  /// first time it is seen and each time it comes onto a screen or leaves it.
  init(log: ProbeLog) {
    self.log = log
    timer = DispatchSource.makeTimerSource(queue: queue)
    timer.setEventHandler { [weak self] in
      self?.check()
    }
    timer.schedule(deadline: .now(), repeating: .milliseconds(20))
    timer.resume()
  }

  private func check() {
    guard !stopped else { return }
    checks += 1
    let all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    for window in all where (window[kCGWindowOwnerPID as String] as? pid_t) == getpid() {
      let number = window[kCGWindowNumber as String] as? Int ?? 0
      let onScreen = window[kCGWindowIsOnscreen as String] as? Bool ?? false
      let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
      let layer = window[kCGWindowLayer as String] as? Int ?? 0
      let state = "on screen \(onScreen), alpha \(alpha), layer \(layer)"
      if known[number] != state {
        known[number] = state
        log.note("screen check: window \(number) \(state)")
      }
    }
  }

  /// Stops watching and writes how often it looked, the first time.
  func stop() {
    timer.cancel()
    queue.sync {
      guard !stopped else { return }
      stopped = true
      log.note("screen check: \(checks) checks, stopped")
    }
  }
}

/// The queue of events of the app, which takes events from any thread.
///
/// `postEvent(_:atStart:)` is documented as safe to call from any thread, but Swift sees only
/// that `NSApplication` belongs to the main actor; so it is called through its implementation.
struct ProbeEventQueue: @unchecked Sendable {
  private typealias PostEvent = @convention(c) (AnyObject, Selector, NSEvent, ObjCBool) -> Void

  private let application: NSApplication
  private let post: PostEvent
  private static let selector = #selector(NSApplication.postEvent(_:atStart:))

  /// The queue of `application`.
  init(application: NSApplication) {
    self.application = application
    post = unsafeBitCast(
      class_getMethodImplementation(NSApplication.self, Self.selector), to: PostEvent.self)
  }

  /// Puts `event` at the end of the queue, behind the events the system sent before.
  func post(_ event: NSEvent) {
    post(application, Self.selector, event, false)
  }
}

/// Flicks of two fingers on a trackpad, as events the copy posts to itself over a point of a
/// window: the fingers move for a quarter of a second, then the content glides on, at 120 events
/// a second, down and up again.
///
/// The events go into the queue of the app from a thread of their own, at the times a trackpad
/// sends them, and wait there while the main thread is busy, as the events of the system do.
/// AppKit glides on by itself from the speed of the fingers as they lift; the events of the
/// momentum phase only carry the phase, as AppKit takes no distance from them.
struct ProbeFlicks: Sendable {
  /// The number of the window the events go to.
  var window: Int

  /// The point of the window, in its coordinates, that the events go to.
  var point: CGPoint

  /// The flicks down, and as many up.
  var count: Int

  /// The time between two events.
  static let interval: TimeInterval = 1 / 120.0

  /// Plays the flicks into `queue` and returns when the first event went out and when the last
  /// did, on the clock of the display link.
  func play(into queue: ProbeEventQueue) -> (start: CFTimeInterval, end: CFTimeInterval) {
    var events: [(delta: Double, phase: Int64, momentum: Int64)] = []
    var pauses: [Int] = []
    for flick in 0..<(2 * count) {
      let direction: Double = flick < count ? -1 : 1
      events.append((0, 1, 0))
      for step in 0..<30 { events.append((direction * Double(4 + step), 2, 0)) }
      events.append((0, 4, 0))
      var delta = direction * 34
      events.append((delta, 0, 1))
      for _ in 0..<180 {
        delta *= 0.975
        events.append((delta, 0, 2))
      }
      events.append((0, 0, 3))
      pauses.append(events.count)
    }
    let start = CACurrentMediaTime()
    var due = start
    var pauseIterator = pauses.makeIterator()
    var nextPause = pauseIterator.next()
    for (index, event) in events.enumerated() {
      if index == nextPause {
        // A fifth of a second between two flicks.
        due += 0.2
        nextPause = pauseIterator.next()
      }
      let wait = due - CACurrentMediaTime()
      if wait > 0 {
        Thread.sleep(forTimeInterval: wait)
      }
      if let scroll = ProbeEvents.scroll(
        delta: event.delta, phase: event.phase, momentum: event.momentum, window: window,
        at: point)
      {
        queue.post(scroll)
      }
      due += Self.interval
    }
    return (start, CACurrentMediaTime())
  }
}

/// Events of a trackpad, made for the copy itself.
enum ProbeEvents {
  /// An event of a trackpad that scrolls by `delta` points, positive upwards, in the phase of
  /// the fingers `phase` and of the momentum `momentum`, as the fields of `CGEvent` number
  /// them, over `point` of the window numbered `window`.
  ///
  /// `CGEvent` makes events of the scroll wheel only for the system: it has no public field for
  /// the window that `NSEvent` reads. So the event starts as a movement of the mouse in the
  /// window, which has it, and turns into one of the scroll wheel.
  static func scroll(
    delta: Double, phase: Int64, momentum: Int64, window: Int, at point: CGPoint
  ) -> NSEvent? {
    guard
      let event = NSEvent.mouseEvent(
        with: .mouseMoved, location: point, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window, context: nil,
        eventNumber: 0, clickCount: 0, pressure: 0)?.cgEvent
    else { return nil }
    event.type = .scrollWheel
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
    event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(delta.rounded()))
    event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: delta)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: delta)
    return NSEvent(cgEvent: event)
  }
}
