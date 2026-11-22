import AppKit
import MergeModel
import os

/// The files behind the window: watched on disk and reloaded when they change, and chosen anew
/// with Change Files.
extension SessionWindowController {
  /// Watches the files of the session and the file of the result, each once; files watched
  /// already go on being watched.
  func watchFiles() {
    var urls = presentation.changes.session.inputs.values.compactMap(\.url)
    if let url = saving?.url {
      urls.append(url)
    }
    diskWatch.watch(urls)
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
    guard await prompts.confirmReloadingChangedFile(url.lastPathComponent, in: window) else {
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
    resultUndo.carryOut(result.document.planResolvingOpenConflicts(with: []), named: name)
    if let result = presentation.result {
      let replacement = TextReplacement(range: 0..<result.text.utf16.count, text: text)
      resultUndo.carryOut(result.document.plan(for: replacement), named: name)
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
  ///
  /// A file of a comparison with copied changes is not reloaded without asking: a sheet offers
  /// to keep the window's version, which Save writes over the file later, or to reload it. A
  /// file without such changes reloads at once.
  private func reloadChangedSources() async {
    let session = presentation.changes.session
    var changed: [Role: SourceFile] = [:]
    for (role, file) in session.inputs {
      guard let url = file.url,
        let bytes = FileManager.default.contents(atPath: url.path(percentEncoded: false)),
        bytes != filesOnDisk[url] ?? file.bytes, !diskWatch.hasSeen(bytes, at: url)
      else { continue }
      changed[role] = SourceFile(bytes: bytes, label: file.label, url: url)
    }
    guard !changed.isEmpty else { return }
    collectionNavigator?.shownFileChangedOnDisk()
    // Reloaded or not, the window has seen these bytes: it asks no more about them, and an undo
    // that brings back the files before stays.
    for file in changed.values {
      if let url = file.url {
        diskWatch.remember(file.bytes, at: url)
      }
    }
    var reloaded = changed
    if let window {
      for (role, file) in changed where editedRoles.contains(role) {
        guard let url = file.url else { continue }
        let name = url.lastPathComponent
        if !(await prompts.confirmReloadingChangedFile(name, in: window)) {
          // The file no longer holds what the window knew of it; the window's version stays
          // unsaved.
          filesOnDisk.note(file.bytes, at: url)
          reloaded[role] = nil
        }
      }
    }
    guard !reloaded.isEmpty else {
      updateEditedFiles()
      stateDidChange()
      return
    }
    await reloadFiles(reloaded)
  }

  /// Compares the files of the session anew with `files` in their roles, as they are on disk
  /// now, as one step of undo; asks first if decisions of a merge would be lost.
  func reloadFiles(_ files: [Role: SourceFile]) async {
    let session = presentation.changes.session
    let inputs = session.inputs.mapValuesWithRoles { role, file in files[role] ?? file }
    guard let reloaded = await compare(inputs, as: session) else { return }
    if session.kind == .diff {
      filesOnDisk.noteRead(files.values)
    }
    let name =
      files.count == 1 ? files.keys.first.flatMap { presentation.headers[$0]?.distinctName } : nil
    await replaceSession(with: reloaded) { count, window in
      await self.prompts.confirmReloading(name, discarding: count, in: window)
    }
  }

  /// The comparison of `files` in the kind and with the options and ignore rules of `session`,
  /// or `nil` if they cannot be compared, such as after one became binary; the window then keeps
  /// what it shows.
  private func compare(
    _ files: Session.Inputs<SourceFile>, as session: Session
  ) async -> Session? {
    do {
      switch session.kind {
      case .merge:
        return try await Session.merge(
          base: files.base, a: files.a, b: files.b, options: session.options)
      case .diff:
        return try await Session.diff(
          old: files.a, new: files.b, mode: session.options.mode, ignoring: session.ignoreRules)
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
      show(await prepared(.comparison(session)), named: Self.reloadName)
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
      let prepared = await prepared(.merge(reload.result))
      guard isShowing(result) else { continue }
      show(prepared, named: Self.reloadName)
      return true
    }
    return false
  }

  /// What reloading `result` with `session`, a comparison of the files as they are now, makes
  /// of it: the result of the new merge with each decision that belongs to the same block
  /// without doubt, and how many decisions it discards; worked out away from the main actor.
  @concurrent
  private static func reloading(
    _ result: ResultState, to session: Session
  ) async -> (result: ResultState, discardedDecisionCount: Int) {
    let reload = result.document.planReloading(to: session, text: result.text)
    var document = result.document
    _ = document.apply(reload.plan, replacedTexts: [result.text])
    return (
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
      purpose: .change(presentation.changes.session.kind), displayOptions: displayOptions,
      panels: SystemPanels(), window: sheetWindow
    ) { [weak self] text in self?.presentation.announce(text) }
    sheet.fill(comparison)
    sheet.onOpen = { [weak self] comparison in try await self?.changeFiles(to: comparison) }
    changeFilesSheet = sheet
    window.beginSheet(sheetWindow) { [weak self] _ in self?.changeFilesSheet = nil }
  }

  /// The files of the window in their roles, or `nil` if a file was not read from disk.
  var fileComparison: FileComparison? {
    let files = presentation.changes.session.inputs
    guard let left = files.a.url, let right = files.b.url else { return nil }
    let base = files.base
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
    guard await saveChangedFilesAskingFirst() else { return }
    if session.kind == .diff {
      filesOnDisk.noteRead(session.inputs.values)
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

extension SessionWindowController: DiskWatchDelegate {
  /// Whether the window can reload its files: none once it closed or while it shows why they
  /// cannot be compared, and none yet while it saves, compares or waits for their lines.
  func readinessToReload(for watch: DiskWatch) -> DiskWatch.Readiness {
    if hasFinished || phase.unavailable != nil {
      return .nothingToReload
    }
    return comparisonSwitcher.isComparing || isSaving || waitsForComparison ? .busy : .ready
  }

  /// Reloads what changed on disk: asks about a result file that another app changed, and
  /// compares the files of the session anew, keeping the decisions that belong to the same
  /// blocks, after asking if others would be lost.
  func reloadChangedFiles(for watch: DiskWatch) async {
    await reloadChangedResult()
    await reloadChangedSources()
  }
}
