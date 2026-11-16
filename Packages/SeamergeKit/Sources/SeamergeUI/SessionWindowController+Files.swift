import AppKit
import MergeModel

/// The files behind the window: watched on disk and reloaded when they change, and chosen anew
/// with Change Files.
extension SessionWindowController {
  /// Watches the files of the session and the file of the result, each once; files watched
  /// already go on being watched.
  func watchFiles() {
    let session = presentation.changes.session
    var urls = session.roles.compactMap { session.file(for: $0)?.url }
    if let url = saving?.url {
      urls.append(url)
    }
    let unique = urls.reduce(into: [URL]()) { unique, url in
      if !unique.contains(url) {
        unique.append(url)
      }
    }
    guard unique != fileWatchers.map(\.url) else { return }
    fileWatchers = unique.map { url in
      FileWatcher(url: url) { [weak self] in self?.filesMayHaveChanged() }
    }
  }

  /// Looks at the files soon, once for every change that arrives before.
  func filesMayHaveChanged() {
    guard !hasFinished, !isReloadPending else { return }
    isReloadPending = true
    Task { await reloadChangedFiles() }
  }

  /// Reloads what changed on disk: asks about a result file that another app changed, and
  /// compares the files of the session anew, keeping the decisions that belong to the same
  /// blocks, after asking if others would be lost.
  ///
  /// While the window reloads, saves or compares its files already, it looks again afterwards.
  func reloadChangedFiles() async {
    isReloadPending = false
    guard !hasFinished, unavailable == nil else { return }
    guard !isReloading, !isSwitchingComparison, !isSaving, !waitsForComparison else {
      looksAtFilesAgain = true
      return
    }
    isReloading = true
    defer {
      isReloading = false
      lookAtFilesAgainIfAsked()
    }
    await reloadChangedResult()
    await reloadChangedSources()
  }

  /// Looks at the files once more if they may have changed while the window was busy.
  func lookAtFilesAgainIfAsked() {
    guard looksAtFilesAgain else { return }
    looksAtFilesAgain = false
    filesMayHaveChanged()
  }

  /// Asks whether to reload the result file if another app changed it: keeping the window's
  /// version leaves it to be saved over the file, so the window counts as unsaved; reloading
  /// takes the file's text as the result, as a step of undo.
  private func reloadChangedResult() async {
    guard var saving, let url = saving.url, let window,
      let bytes = FileManager.default.contents(atPath: url.path(percentEncoded: false)),
      bytes != saving.diskBytes
    else { return }
    saving.diskBytes = bytes
    self.saving = saving
    guard await prompts.confirmReloadingChangedResult(url.lastPathComponent, in: window) else {
      // The file no longer holds what the window shows.
      if var saving = self.saving {
        saving.saved = nil
        self.saving = saving
      }
      stateDidChange()
      return
    }
    guard let text = SourceFile(bytes: bytes, label: url.lastPathComponent).text else { return }
    takeOverResult(text)
  }

  /// Makes `text`, that of the result file, the result, as one step of undo: every open
  /// conflict is resolved, and the text replaces the whole result as if typed.
  ///
  /// The window then shows what the file holds, so it counts as saved, as a document reverted
  /// to its file does; undo takes it back to unsaved.
  func takeOverResult(_ text: String) {
    guard let result = presentation.result else { return }
    let name = Self.reloadName
    sessionUndoManager.beginUndoGrouping()
    carryOut(result.document.planResolvingOpenConflicts(with: []), named: name)
    if let result = presentation.result {
      let replacement = TextReplacement(range: 0..<result.text.utf16.count, text: text)
      carryOut(result.document.plan(for: replacement), named: name)
    }
    sessionUndoManager.endUndoGrouping()
    if var saving, let result = presentation.result {
      saving.saved = SavedResult(
        result, session: presentation.changes.session, format: saving.format)
      self.saving = saving
    }
    stateDidChange()
  }

  /// Compares the files of the session anew if one of them changed on disk.
  private func reloadChangedSources() async {
    let session = presentation.changes.session
    var files: [Role: SourceFile] = [:]
    var changed: [Role] = []
    for role in session.roles {
      guard let file = session.file(for: role) else { continue }
      guard let url = file.url,
        let bytes = FileManager.default.contents(atPath: url.path(percentEncoded: false)),
        bytes != file.bytes, seenOnDisk[url] != bytes
      else {
        files[role] = file
        continue
      }
      files[role] = SourceFile(bytes: bytes, label: file.label, url: url)
      changed.append(role)
    }
    guard !changed.isEmpty, let reloaded = await compare(files, as: session) else { return }
    let name = changed.count == 1 ? presentation.headers[changed[0]]?.distinctName : nil
    await replaceSession(with: reloaded) { count, window in
      await self.prompts.confirmReloading(name, discarding: count, in: window)
    }
    // Reloaded or not, the window has seen these bytes: it asks no more about them, and an undo
    // that brings back the files before stays.
    for role in changed {
      if let file = files[role], let url = file.url {
        seenOnDisk[url] = file.bytes
      }
    }
  }

  /// The comparison of `files` in the kind and with the options and ignore rules of `session`,
  /// or `nil` if they cannot be compared, such as after one became binary; the window then keeps
  /// what it shows.
  private func compare(_ files: [Role: SourceFile], as session: Session) async -> Session? {
    guard let a = files[.a], let b = files[.b] else { return nil }
    do {
      switch session.kind {
      case .merge:
        return try await Session.merge(base: files[.base], a: a, b: b, options: session.options)
      case .diff:
        return try await Session.diff(
          old: a, new: b, mode: session.options.mode, ignoring: session.ignoreRules)
      }
    } catch {
      Self.logger.notice("The changed files cannot be compared: \(error, privacy: .public)")
      return nil
    }
  }

  /// Shows `session`, a comparison of the files of the window as they are now, keeping each
  /// decision that belongs to the same block without doubt, as one step of undo; tells whether
  /// it did.
  ///
  /// If decisions would be lost, `ask` asks first with their number.
  @discardableResult
  private func replaceSession(
    with session: Session, askingWith ask: (Int, NSWindow) async -> Bool
  ) async -> Bool {
    guard let window else { return false }
    guard presentation.result != nil else {
      show(await prepared(session, result: nil), named: Self.reloadName)
      return true
    }
    // The user may decide or type while the new comparison is made ready; it then starts over
    // from the result as it is now.
    while let result = presentation.result {
      let reload = await Self.reloading(result, to: session)
      if reload.discardedDecisionCount > 0 {
        guard await ask(reload.discardedDecisionCount, window) else { return false }
        // Asking took a moment; a decision made meanwhile goes into the reload as well.
        guard isShowing(result) else { continue }
      }
      let prepared = await prepared(reload.session, result: reload.result)
      guard isShowing(result) else { continue }
      show(prepared, named: Self.reloadName)
      return true
    }
    return false
  }

  /// What reloading `result` with `session`, a comparison of the files as they are now, makes
  /// of it: the session and the result with each decision that belongs to the same block
  /// without doubt, and how many decisions it discards; worked out away from the main actor.
  @concurrent
  private static func reloading(
    _ result: ResultState, to session: Session
  ) async -> (session: Session, result: ResultState, discardedDecisionCount: Int) {
    let reload = result.document.planReloading(to: session, text: result.text)
    var document = result.document
    _ = document.apply(reload.plan, replacedTexts: [result.text])
    return (
      document.session,
      ResultState(document: document, text: reload.plan.replacements.map(\.text).joined()),
      reload.discardedDecisionCount
    )
  }

  /// What Undo calls reloading files that changed on disk, and the button of the sheets that
  /// ask whether to.
  static var reloadName: String {
    String(
      localized: "Reload", bundle: .module,
      comment:
        "Files that changed on disk: the button of a sheet that offers to show them as they are now, and the step of the Undo menu that did."
    )
  }

  /// Asks in a sheet for other files in the roles of the window, filled with those it shows,
  /// and compares those in their place.
  @objc func changeFiles(_ sender: Any?) {
    guard canPerform(.changeFiles), changeFilesSheet == nil, let window,
      let comparison = fileComparison
    else { return }
    let sheetWindow = CompareFilesWindow()
    let sheet = CompareFilesWindowController(
      recentComparisons: RecentComparisons(defaults: settings.defaults),
      displayOptions: displayOptions, panels: SystemPanels(), window: sheetWindow,
      purpose: .change(presentation.changes.session.kind)
    ) { [weak self] text in self?.presentation.announce(text) }
    sheet.fill(comparison)
    sheet.onChange = { [weak self] comparison in try await self?.changeFiles(to: comparison) }
    changeFilesSheet = sheet
    window.beginSheet(sheetWindow) { [weak self] _ in self?.changeFilesSheet = nil }
  }

  /// The files of the window in their roles, or `nil` if a file was not read from disk.
  var fileComparison: FileComparison? {
    let session = presentation.changes.session
    guard let left = session.file(for: .a)?.url, let right = session.file(for: .b)?.url else {
      return nil
    }
    let base = session.file(for: .base)
    guard base == nil || base?.url != nil else { return nil }
    return FileComparison(left: left, base: base?.url, right: right)
  }

  /// Compares the files of `comparison` in place of those the window shows, in its comparison
  /// mode, keeping each decision that belongs to the same block without doubt, as one step of
  /// undo; ends the sheet of Change Files once the files are read, and asks first if decisions
  /// would be lost.
  ///
  /// - Throws: Why the files cannot be compared, before anything changes.
  func changeFiles(to comparison: FileComparison) async throws(SessionLoadingError) {
    let file = { (url: URL) in SessionFile(url: url, label: url.lastPathComponent) }
    let mode = comparisonOptions.mode
    let session =
      if let base = comparison.base {
        try await Session.loadMerge(
          base: file(base), a: file(comparison.left), b: file(comparison.right), mode: mode)
      } else {
        try await Session.loadDiff(
          old: file(comparison.left), new: file(comparison.right), mode: mode)
      }
    if let window, let sheetWindow = changeFilesSheet?.window {
      window.endSheet(sheetWindow)
    }
    let isReplaced = await replaceSession(with: session) { count, window in
      await self.prompts.confirmChangingFiles(discarding: count, in: window)
    }
    guard isReplaced, var saving else { return }
    saving.format = ResultFormat(resultOf: session)
    self.saving = saving
    showResultFormat()
    stateDidChange()
  }
}
