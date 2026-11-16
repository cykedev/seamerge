import AppKit
import MergeModel
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
    try await open(
      [.base: base, .a: a, .b: b].compactMapValues(\.self), kind: .merge, mode: mode,
      context: context, undoManager: undoManager, settings: settings
    ) { files throws(SessionLoadingError) in
      guard let aFile = files[.a], let bFile = files[.b] else {
        preconditionFailure("A merge has the inputs A and B")
      }
      do throws(MergeModelError) {
        return try await Session.merge(
          base: files[.base], a: aFile, b: bFile, options: ComparisonOptions(mode: mode))
      } catch {
        throw SessionLoadingError(
          error, files: [.base: base, .a: a, .b: b].compactMapValues(\.self))
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
    try await open(
      [.a: old, .b: new], kind: .diff, mode: mode, context: context,
      undoManager: undoManager, settings: settings
    ) { files throws(SessionLoadingError) in
      guard let a = files[.a], let b = files[.b] else {
        preconditionFailure("A comparison has the inputs A and B")
      }
      do throws(MergeModelError) {
        return try await Session.diff(old: a, new: b, mode: mode, ignoring: rules)
      } catch {
        throw SessionLoadingError(error, files: [.a: old, .b: new])
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
    _ files: [Role: SessionFile], kind: Session.Kind, mode: ComparisonMode,
    context: SessionContext, undoManager: UndoManager, settings: UserSettings,
    waitingAtMost wait: TimeInterval = comparisonWait,
    compare: @escaping @Sendable ([Role: SourceFile]) async throws(SessionLoadingError) -> Session
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
      await controller.comparisonFill?.value
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
  /// before the toolbar says that it is under way, in seconds.
  static let openingProgressDelay: TimeInterval = 0.5

  /// The outcome of `comparison` if it is there within `delay` seconds, or `nil`.
  static func outcome(
    of comparison: PendingComparison, within delay: TimeInterval
  ) async -> Result<Session, SessionLoadingError>? {
    let first = FirstOutcome()
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
    of files: [Role: SessionFile], kind: Session.Kind, mode: ComparisonMode
  ) async throws(SessionLoadingError) -> Session {
    let empty = { (role: Role) in
      files[role].map { SourceFile(bytes: Data(), label: $0.label, url: $0.url) }
    }
    guard let a = empty(.a), let b = empty(.b) else {
      preconditionFailure("Every session has the inputs A and B")
    }
    do {
      switch kind {
      case .merge:
        return try await Session.merge(
          base: empty(.base), a: a, b: b, options: ComparisonOptions(mode: mode))
      case .diff:
        return try await Session.diff(old: a, new: b, mode: mode)
      }
    } catch {
      throw .comparisonFailed
    }
  }

  /// Whether the window waits for the comparison of its files, with their headers and empty
  /// panes.
  var waitsForComparison: Bool {
    comparisonFill != nil
  }

  /// Waits for `comparison` with the headers of the files and empty panes, which say so to
  /// VoiceOver; once the comparison has taken a moment, the toolbar says so too.
  func wait(for comparison: PendingComparison) {
    for pane in presentation.allPanes {
      pane.documentView.setAccessibilityPlaceholderValue(SessionToolbar.comparingText)
    }
    // The result has no line yet, and no format; an empty result would number its first.
    layout.resultPane?.setContent(.empty, collapsedRuns: [])
    if var header = layout.resultHeader {
      header.format = nil
      layout.show(header)
    }
    let progressTimer = Timer(timeInterval: Self.openingProgressDelay, repeats: false) {
      [weak self] _ in
      // Timers of the main run loop fire on the main thread.
      MainActor.assumeIsolated {
        guard let self, self.waitsForComparison else { return }
        self.showsComparisonProgress = true
        self.stateDidChange()
      }
    }
    RunLoop.main.add(progressTimer, forMode: .common)
    comparisonFill = Task { [weak self] in
      let outcome = await comparison.value
      progressTimer.invalidate()
      await self?.fill(with: outcome)
    }
    sessionDidChange()
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
    switch outcome {
    case .success(let session):
      let headers = Dictionary(
        uniqueKeysWithValues: session.roles.map { role in
          (role, SideHeader(role: role, session: session, context: context))
        })
      presentation.show(headers)
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
      guard let old = file(of: .a, in: session), let new = file(of: .b, in: session) else {
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
    for pane in presentation.allPanes {
      pane.documentView.setAccessibilityPlaceholderValue(nil)
    }
    comparisonFill = nil
    showsComparisonProgress = false
    sessionDidChange()
    showResultFormat()
    watchFiles()
    stateDidChange()
    lookAtFilesAgainIfAsked()
    followIgnoreRules()
    // A window that fills before it shows says nothing: VoiceOver reads it as it appears.
    guard window?.isVisible == true else { return }
    presentation.announce(failure ?? comparedAnnouncement)
  }

  /// What VoiceOver hears once the files of a window that showed without their lines are
  /// compared: that they are, and how many changes or open conflicts they have.
  private var comparedAnnouncement: String {
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

  /// The file of the window in `role`, as the session without lines names it.
  private func file(of role: Role, in session: Session) -> SessionFile? {
    guard let file = session.file(for: role), let url = file.url else { return nil }
    return SessionFile(url: url, label: file.label)
  }

  /// Lets the lines fade in where the empty panes stood, unless movement is reduced or the
  /// window does not show yet.
  private func fadeInTheLines() {
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
private final class FirstOutcome {
  var continuation: CheckedContinuation<Result<Session, SessionLoadingError>?, Never>?

  func resume(with outcome: Result<Session, SessionLoadingError>?) {
    continuation?.resume(returning: outcome)
    continuation = nil
  }
}
