public import AppKit
public import MergeModel
import PaneKit
import Synchronization

/// The comparison of the files of a window that opens before it is ready, which the window
/// waits for with the headers of its files and empty panes.
typealias PendingComparison = Task<Result<Session, SessionLoadingError>, Never>

extension SessionWindowController {
  /// Opens a window for the merge of `a` and `b`, with `base` if there is one, read and merged in
  /// the comparison mode `mode`, as a window for ``init(session:context:undoManager:settings:)``.
  ///
  /// The files are read before the window opens. A merge that is ready soon opens as it is. A
  /// longer one opens with the headers of the files and empty panes, which fill once it is
  /// ready; should it then fail, the window says why in place of the lines.
  ///
  /// - Throws: ``SessionLoadingError`` with the file that cannot be read or is not text, or why
  ///   the files cannot be merged if that is known before the window opens.
  public static func openMerge(
    base: SessionFile?, a: SessionFile, b: SessionFile, mode: ComparisonMode,
    context: SessionContext, undoManager: UndoManager, settings: UserSettings
  ) async throws(SessionLoadingError) -> SessionWindowController {
    let files = Session.Inputs(base: base, a: a, b: b)
    return try await open(
      files, kind: .merge, mode: mode, context: context, undoManager: undoManager,
      settings: settings
    ) { read throws(SessionLoadingError) in
      do throws(MergeModelError) {
        return try await Session.merge(
          base: read.base, a: read.a, b: read.b, options: ComparisonOptions(mode: mode))
      } catch {
        throw SessionLoadingError(error, files: files)
      }
    }
  }

  /// Opens a window for the comparison of the older file `old` with the newer file `new`, read
  /// and compared in the comparison mode `mode` without the text that the enabled rules of
  /// `rules` match, as a window for ``init(session:context:undoManager:settings:)``.
  ///
  /// The files are read before the window opens. A comparison that is ready soon opens as it is.
  /// A longer one opens with the headers of the files and empty panes, which fill once it is
  /// ready; should it then fail, the window says why in place of the lines.
  ///
  /// - Throws: ``SessionLoadingError`` with the file that cannot be read or is not text, or why
  ///   the files cannot be compared if that is known before the window opens.
  public static func openDiff(
    old: SessionFile, new: SessionFile, mode: ComparisonMode, ignoring rules: [IgnoreRule] = [],
    context: SessionContext, undoManager: UndoManager, settings: UserSettings
  ) async throws(SessionLoadingError) -> SessionWindowController {
    let files = Session.Inputs(a: old, b: new)
    return try await open(
      files, kind: .diff, mode: mode, context: context, undoManager: undoManager,
      settings: settings
    ) { read throws(SessionLoadingError) in
      do throws(MergeModelError) {
        return try await Session.diff(old: read.a, new: read.b, mode: mode, ignoring: rules)
      } catch {
        throw SessionLoadingError(error, files: files)
      }
    }
  }

  /// Reads `files` and opens a window for the session of `kind` that `compare` makes of them in
  /// the comparison mode `mode`.
  ///
  /// The window waits for the comparison with the headers of the files and empty panes. A
  /// comparison that is there within `wait` seconds, ``comparisonWait`` unless told otherwise,
  /// fills the window before it returns, so that it shows filled; otherwise the window returns
  /// to show while it waits.
  static func open(
    _ files: Session.Inputs<SessionFile>, kind: Session.Kind, mode: ComparisonMode,
    context: SessionContext, undoManager: UndoManager, settings: UserSettings,
    waitingAtMost wait: TimeInterval = comparisonWait,
    compare:
      @escaping @Sendable (Session.Inputs<SourceFile>) async throws(SessionLoadingError) -> Session
  ) async throws(SessionLoadingError) -> SessionWindowController {
    let start = ContinuousClock.now
    let read = try await Session.read(files)
    // The comparison may end while the window is made, before anyone can wait for it. It runs
    // detached, so that it notes its outcome the moment it is there, not once the main actor,
    // which makes the window meanwhile, is free.
    let arrived = Mutex<Result<Session, SessionLoadingError>?>(nil)
    let comparison = PendingComparison.detached(priority: .userInitiated) {
      let outcome: Result<Session, SessionLoadingError>
      do throws(SessionLoadingError) {
        outcome = .success(try await compare(read))
      } catch {
        outcome = .failure(error)
      }
      arrived.withLock { $0 = outcome }
      return outcome
    }
    let controller = SessionWindowController(
      session: try await emptySession(of: files, kind: kind, mode: mode), context: context,
      undoManager: undoManager, displayOptions: .current(in: .shared), pasteboard: .general,
      workspace: NSWorkspace.shared, prompts: SessionSheets(), doneStyle: .standard,
      settings: settings, syntaxChoices: .shared, window: SessionWindow(),
      pendingComparison: comparison)
    controller.observeDisplayOptions()
    var outcome = arrived.withLock { $0 }
    let waited = (ContinuousClock.now - start) / .seconds(1)
    if outcome == nil, waited < wait {
      outcome = await Self.outcome(of: comparison, within: wait - waited)
    }
    if let outcome {
      // The window of files that cannot be compared does not show; the caller tells why.
      if case .failure(let reason) = outcome {
        throw reason
      }
      await controller.phase.filling?.value
    }
    return controller
  }

  /// How long a window that opens waits for the comparison of its files before it shows
  /// without their lines, in seconds.
  ///
  /// A window that showed empty and filled a moment later would flash at every small
  /// comparison; one that waits much longer keeps the user waiting for nothing to show. With
  /// the time it takes to draw, the window shows within about 150 ms either way.
  static let comparisonWait: TimeInterval = 0.08

  /// How long a window that opens without the lines of its files waits for their comparison
  /// before the toolbar says that it is under way.
  static let openingProgressDelay: Duration = .milliseconds(500)

  /// The outcome of `comparison` if it is there within `delay` seconds, or `nil`.
  static func outcome<Outcome: Sendable>(
    of comparison: Task<Outcome, Never>, within delay: TimeInterval
  ) async -> Outcome? {
    let first = FirstOutcome<Outcome>()
    return await withCheckedContinuation { continuation in
      first.continuation = continuation
      let timer = Timer(timeInterval: delay, repeats: false) { _ in
        // Timers of the main run loop fire on the main thread.
        MainActor.assumeIsolated { first.resume(with: nil) }
      }
      RunLoop.main.add(timer, forMode: .common)
      Task {
        let outcome = await comparison.value
        timer.invalidate()
        first.resume(with: outcome)
      }
    }
  }

  /// The session that names the files of `files` in the headers of a window of `kind` without
  /// their lines, while their comparison in the comparison mode `mode` is under way.
  ///
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if even that fails.
  static func emptySession(
    of files: Session.Inputs<SessionFile>, kind: Session.Kind, mode: ComparisonMode
  ) async throws(SessionLoadingError) -> Session {
    let empty = files.mapValues { SourceFile(bytes: Data(), label: $0.label, url: $0.url) }
    do {
      switch kind {
      case .merge:
        return try await Session.merge(
          base: empty.base, a: empty.a, b: empty.b, options: ComparisonOptions(mode: mode))
      case .diff:
        return try await Session.diff(old: empty.a, new: empty.b, mode: mode)
      }
    } catch {
      throw .comparisonFailed
    }
  }

  /// Whether the window waits for the comparison of its files, with their headers and empty
  /// panes.
  var waitsForComparison: Bool {
    phase.filling != nil
  }

  /// Waits for `comparison` with the headers of the files and empty panes, which say so to
  /// VoiceOver; once the comparison has taken a moment, the toolbar says so too.
  func wait(for comparison: PendingComparison) {
    beginWaiting(
      filling: Task { [weak self] in
        let outcome = await comparison.value
        await self?.fill(with: outcome)
      })
  }

  /// Waits with the headers of the files and empty panes, which say so to VoiceOver, while
  /// `filling` gets the lines ready; once that has taken a moment, the toolbar says so too.
  ///
  /// The window takes no command of the lines until ``endWaiting()``. A wait that begins while
  /// another goes on takes its place.
  func beginWaiting(filling: Task<Void, Never>) {
    for pane in presentation.allPanes {
      pane.documentView.setAccessibilityPlaceholderValue(SessionToolbar.comparingText)
    }
    // The result has no line yet, and no format; an empty result would number its first.
    layout.resultPane?.setContent(.empty, collapsedRuns: [])
    if var header = layout.resultHeader {
      header.format = nil
      layout.show(header)
    }
    phase = .loading(filling)
    let progress = Task { [weak self] in
      do {
        try await Task.sleep(for: Self.openingProgressDelay)
      } catch {
        // The lines were ready before it took a moment.
        return
      }
      guard let self, phase.filling == filling else { return }
      showsComparisonProgress = true
      stateDidChange()
    }
    Task {
      await filling.value
      progress.cancel()
    }
    sessionDidChange()
  }

  /// Ends the wait for the lines, which are there now or cannot be; the window shows the lines
  /// until it says why it cannot.
  func endWaiting() {
    for pane in presentation.allPanes {
      pane.documentView.setAccessibilityPlaceholderValue(nil)
    }
    phase = .ready
    showsComparisonProgress = false
  }

  /// Shows the outcome of the comparison the window waited for: the session in every pane, from
  /// its first open conflict or change, or why the files cannot be compared in place of the
  /// lines; VoiceOver hears which, unless the window does not show yet.
  ///
  /// A window that closed meanwhile shows nothing and makes nothing ready.
  private func fill(with outcome: Result<Session, SessionLoadingError>) async {
    guard !hasFinished else { return }
    // What the window says once the files cannot be compared, which VoiceOver hears as well.
    var failure: String?
    var unavailable: UnavailableComparison?
    switch outcome {
    case .success(let session):
      presentation.show(SideHeader.headers(of: session, context: context))
      let prepared = await presentation.prepareLoaded(session)
      guard !hasFinished else { return }
      fadeInTheLines()
      presentation.showLoaded(prepared)
      saving = presentation.result.map {
        ResultSaving(result: $0, session: session, url: context.resultURL)
      }
      detectedLanguage = SessionSyntax.language(of: session, resultURL: context.resultURL)
      syntaxPath = SessionSyntax.path(of: session, resultURL: context.resultURL)
      presentation.colorSyntax(as: syntaxLanguage)
    case .failure(let reason):
      let session = presentation.changes.session
      guard let old = Self.file(session.inputs.a), let new = Self.file(session.inputs.b) else {
        return
      }
      let comparison = UnavailableComparison(old: old, new: new, reason: reason)
      unavailable = comparison
      let title =
        session.kind == .merge
        ? String(
          localized:
            "Seamerge can’t merge “\(context.resultURL?.lastPathComponent ?? new.label)”",
          bundle: .module,
          comment: "Merge window: the files cannot be merged, such as “Settings.swift”.")
        : comparison.title
      layout.showInPlaceOfTheLines(
        UnavailableComparisonView(title: title, message: comparison.message(in: context)))
      failure = title
    }
    endWaiting()
    if let unavailable {
      phase = .unavailable(unavailable)
    }
    sessionDidChange()
    showResultFormat()
    watchFiles()
    stateDidChange()
    diskWatch.lookAgainIfAsked()
    followIgnoreRules()
    // A window that fills before it shows says nothing: VoiceOver reads it as it appears.
    guard window?.isVisible == true else { return }
    presentation.announce(failure ?? comparedAnnouncement)
  }

  /// What VoiceOver hears once the files of a window that showed without their lines are
  /// compared: that they are, and how many changes or open conflicts they have.
  var comparedAnnouncement: String {
    let count =
      switch toolbarCount {
      case .changes(_, let total): SessionToolbar.countText(currentChange: nil, changeCount: total)
      default: SessionToolbar.countText(toolbarCount)
      }
    return String(
      localized: "Files compared. \(count)", bundle: .module,
      comment:
        "VoiceOver once the files of a window that showed without their lines are compared, such as Files compared. 12 Changes."
    )
  }

  /// The file of the window that `file` of the session without lines names, if it has a path.
  private static func file(_ file: SourceFile) -> SessionFile? {
    file.url.map { SessionFile(url: $0, label: file.label) }
  }

  /// Lets the lines fade in where the empty panes stood, unless movement is reduced or the
  /// window does not show yet.
  func fadeInTheLines() {
    guard !displayOptions.reducesMotion, window?.isVisible == true, let layer = layout.view.layer
    else { return }
    let transition = CATransition()
    transition.type = .fade
    transition.duration = Self.fadeDuration
    layer.add(transition, forKey: nil)
  }

  /// How long the lines take to fade in, in seconds.
  private static let fadeDuration: CFTimeInterval = 0.15
}

/// The first of two outcomes, which resumes the one waiting for it; the later one goes unheard.
@MainActor
private final class FirstOutcome<Outcome: Sendable> {
  var continuation: CheckedContinuation<Outcome?, Never>?

  func resume(with outcome: Outcome?) {
    continuation?.resume(returning: outcome)
    continuation = nil
  }
}
