import AppKit
import MergeModel
import TextBasics

/// Saving the result of a merge and closing its window, each way out reported exactly once.
extension SessionWindowController {
  /// Writes the result to its file, after asking where the first time if it has none.
  @objc func saveResult(_ sender: Any?) {
    guard canPerform(.save) else { return }
    Task { await save() }
  }

  /// Writes the result to a file that the user chooses.
  ///
  /// A merge that someone waits for keeps its own file: the copy is an export, and Save still
  /// writes to the file the caller reads. Any other merge goes on saving to the chosen file.
  @objc func saveResultAs(_ sender: Any?) {
    guard canPerform(.saveAs) else { return }
    Task { await save(choosingPlace: true) }
  }

  /// Writes the result to its file and closes the window, which reports the session as saved.
  @objc func saveAndClose(_ sender: Any?) {
    guard canPerform(.saveAndClose) else { return }
    Task { await saveAndCloseWindow() }
  }

  /// Writes the result to its file, then closes the window and reports the session as saved,
  /// and tells whether it did; if saving does not happen, the window stays open.
  @discardableResult
  func saveAndCloseWindow() async -> Bool {
    guard await save() else { return false }
    finish(.saved)
    close()
    return true
  }

  /// Closes a merge that Git waits for without saving, so that Git keeps the file unresolved;
  /// asks first if decisions that are not saved would be lost.
  @objc func leaveUnresolved(_ sender: Any?) {
    guard canPerform(.leaveUnresolved) else { return }
    Task { await leaveUnresolvedAskingFirst() }
  }

  /// Closes the window without saving and reports the session as cancelled, after asking if
  /// decisions would be lost, and tells whether it closed.
  ///
  /// Where Git waits, saved decisions count too: Git puts the file back as it was before the
  /// merge when the tool fails, with its conflict markers.
  @discardableResult
  func leaveUnresolvedAskingFirst() async -> Bool {
    if binaryMerge != nil {
      cancel()
      return true
    }
    guard let window, let result = presentation.result else { return false }
    let count = result.document.decisionCount
    let gitPutsBackTheFile = context.waitingCaller == .git
    if count > 0 && (gitPutsBackTheFile || isResultEdited) {
      isAskingToClose = true
      let leaves = await prompts.confirmLeavingUnresolved(
        resultName, discarding: count, gitPutsBackTheFile: gitPutsBackTheFile, in: window)
      isAskingToClose = false
      guard leaves else { return false }
    }
    cancel()
    return true
  }

  /// Whether the result differs from what was saved last; a merge that someone waits for counts
  /// as unsaved until it is saved.
  var isResultEdited: Bool {
    guard let saving, let result = presentation.result else { return false }
    return saving.isEdited(result, session: presentation.changes.session)
  }

  /// The name of the result in a sheet: that of its file, or the title of the window.
  var resultName: String {
    saving?.url?.lastPathComponent ?? window?.title ?? ""
  }

  /// Closes the window, after asking whether to save first while the result has unsaved
  /// changes, and tells whether it closed.
  ///
  /// Saving that fails or is cancelled keeps the window open; closing without saving reports
  /// the session as cancelled.
  @discardableResult
  public func closeAskingFirst() async -> Bool {
    guard !hasFinished else { return true }
    guard isResultEdited, let window, let result = presentation.result else {
      close()
      return true
    }
    guard !isAskingToClose else { return false }
    window.makeKeyAndOrderFront(nil)
    isAskingToClose = true
    let choice = await prompts.confirmClosing(
      resultName, openConflictCount: result.document.openConflictCount,
      caller: context.waitingCaller, in: window)
    isAskingToClose = false
    switch choice {
    case .save:
      guard await save() else { return false }
      finish(.saved)
    case .discard:
      finish(.cancelled)
    case .cancel:
      return false
    }
    close()
    return true
  }

  /// Writes the result to its file, or with `choosingPlace` to one the user chooses, and tells
  /// whether it was written.
  ///
  /// With open conflicts, a sheet asks first and can go to the next one instead. The file is
  /// replaced atomically: a failure leaves it as it was and the window as it is, and a sheet
  /// says why. If the encoding cannot hold the result, a sheet offers UTF-8. Files that change
  /// on disk meanwhile are reloaded only afterwards, so that what is written is what the window
  /// shows.
  @discardableResult
  func save(choosingPlace: Bool = false) async -> Bool {
    guard let window, saving != nil, let shown = presentation.result else { return false }
    isSaving = true
    defer {
      isSaving = false
      diskWatch.lookAgainIfAsked()
    }
    resultUndo.endTypingRun()
    let openCount = shown.document.openConflictCount
    if openCount > 0 {
      switch await prompts.confirmSavingWithOpenConflicts(
        openCount, gitTakesItAsResolved: context.waitingCaller == .git && !choosingPlace,
        in: window)
      {
      case .goToNextConflict:
        let navigation = presentation.navigation
        if let conflict = navigation.nextOpenConflict ?? navigation.firstOpenConflict {
          presentation.jump(to: conflict)
        }
        return false
      case .cancel:
        return false
      case .saveWithMarkers:
        break
      }
    }
    let isExport = choosingPlace && context.waitingCaller != nil
    var url = choosingPlace ? nil : self.saving?.url
    if url == nil {
      url = await prompts.chooseDestination(suggesting: resultName, in: window)
    }
    guard let url else { return false }
    // What the window shows now, after the sheets.
    guard var saving, let result = presentation.result else { return false }
    let content = result.document.exportText(of: result.text, labels: conflictLabels)
    let bytes: Data
    while true {
      // Right before writing, after every sheet: a change by another app is asked about rather
      // than overwritten, and after reloading it the window stays open to show it.
      if url == saving.url, await resultFileChangedAndReloaded(url, in: window) {
        return false
      }
      do {
        bytes = try saving.format.write(content, to: url)
        break
      } catch .unrepresentableText(let encoding) {
        guard await prompts.offerUTF8(saving: url.lastPathComponent, in: encoding, in: window)
        else { return false }
        saving.format = saving.format.with(encoding: .utf8)
      } catch {
        let reason =
          if case .writingFailed(_, let reason) = error { reason } else { "\(error)" }
        await prompts.reportFailedSaving(url.lastPathComponent, reason: reason, in: window)
        return false
      }
    }
    if !isExport {
      saving.url = url
      saving.saved = SavedResult(
        result, session: presentation.changes.session, format: saving.format)
      saving.diskBytes = bytes
      window.representedURL = url
    }
    self.saving = saving
    watchFiles()
    showResultFormat()
    stateDidChange()
    presentation.announce(
      String(
        localized: "Saved \(url.lastPathComponent)", bundle: .module,
        comment: "VoiceOver after saving, such as Saved story.txt."))
    return true
  }

  /// Asks, as a document does, whether to keep the window's version or to reload the result file
  /// at `url` if another app changed it since the window saw it last, and tells whether it
  /// reloaded it; then there is nothing left to write, and saving has not happened.
  ///
  /// The window watches the file, but while it saves, it looks at changes only afterwards; this
  /// look before writing keeps a change of another app from being overwritten unseen.
  private func resultFileChangedAndReloaded(_ url: URL, in window: NSWindow) async -> Bool {
    guard var saving,
      let bytes = FileManager.default.contents(atPath: url.path(percentEncoded: false)),
      bytes != saving.diskBytes
    else { return false }
    saving.diskBytes = bytes
    self.saving = saving
    guard await prompts.confirmReloadingChangedResult(url.lastPathComponent, in: window),
      let text = SourceFile(bytes: bytes, label: url.lastPathComponent).text
    else { return false }
    takeOverResult(text)
    return true
  }

  /// The names written after the conflict markers: those of the headers, on one line each.
  var conflictLabels: ConflictLabels {
    let headers = presentation.headers
    return ConflictLabels(
      a: headers[.a]?.name ?? Role.a.letter, base: headers[.base]?.name ?? "",
      b: headers[.b]?.name ?? Role.b.letter)
  }

  /// Writes the result as `choice` says, as a step of undo.
  @objc func chooseResultFormat(_ sender: Any?) {
    guard let choice = ResultFormatChoice(item: sender) else { return }
    choose(choice)
  }

  /// Writes the result as `choice` says from now on, as a step of undo that brings back the
  /// format before.
  func choose(_ choice: ResultFormatChoice) {
    guard let saving else { return }
    let format =
      switch choice {
      case .encoding(let encoding): saving.format.with(encoding: encoding)
      case .lineEnding(let lineEnding):
        ResultFormat(
          encoding: saving.format.encoding, writesByteOrderMark: saving.format.writesByteOrderMark,
          lineEnding: lineEnding)
      }
    let name =
      switch choice {
      case .encoding:
        String(
          localized: "Change Encoding", bundle: .module,
          comment: "Undo menu: the encoding of the result was changed.")
      case .lineEnding:
        String(
          localized: "Change Line Endings", bundle: .module,
          comment: "Undo menu: the line endings of the result were changed.")
      }
    setResultFormat(format, named: name)
  }

  /// Writes the result in `format` from now on, as a step of undo named `name`.
  private func setResultFormat(_ format: ResultFormat, named name: String) {
    guard var saving, format != saving.format else { return }
    let previous = saving.format
    saving.format = format
    self.saving = saving
    resultUndo.endTypingRun()
    sessionUndoManager.registerUndo(withTarget: self) { controller in
      controller.setResultFormat(previous, named: name)
    }
    sessionUndoManager.setActionName(name)
    showResultFormat()
    stateDidChange()
  }

  /// Shows in the result header how the result is written.
  func showResultFormat() {
    guard let saving, var header = layout.resultHeader else { return }
    header.format = saving.format
    header.path = saving.url.map(ResultHeader.path(of:))
    header.bWithMixedLineEndings =
      presentation.changes.session.inputs.b.lineEndingStyle?.isMixed == true
      ? presentation.headers[.b]?.distinctName : nil
    layout.show(header)
  }

  /// Whether the menu item of `choice` can act, with a checkmark at the format in effect.
  func validate(_ choice: ResultFormatChoice, item: NSMenuItem) -> Bool {
    guard let format = saving?.format, phase.unavailable == nil else {
      item.state = .off
      return false
    }
    item.state =
      switch choice {
      case .encoding(let encoding): encoding == format.encoding ? .on : .off
      case .lineEnding(let lineEnding): lineEnding == format.lineEnding ? .on : .off
      }
    return !isAskingToClose
  }
}
