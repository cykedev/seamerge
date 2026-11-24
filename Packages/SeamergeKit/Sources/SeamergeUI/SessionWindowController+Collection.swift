public import AppKit
public import FolderCompare
import GitSupport
import MergeModel
import PaneKit
import os

/// The comparison of the first file of a collection, which a window that opens without its lines
/// waits for; `nil` if the file cannot even be shown as a file that cannot be compared.
typealias PendingFile = Task<CollectedComparison?, Never>

/// What a window of a collection opens with: the files it names in its headers, without their
/// lines, and the comparison of its first file, while it runs.
struct CollectionOpening {
  /// The empty comparison of the first file that the list shows, or of the two folders while no
  /// such file is known.
  var session: Session

  var context: SessionContext

  /// The comparison of the first file, or `nil` while there is none.
  var comparison: PendingFile?

  /// Which file of the collection the window shows, and which files its list shows, listed
  /// already.
  var navigator: CollectionNavigator
}

/// A file of a collection ready to show: as the window read it, and what its panes show.
private struct ReadyFile {
  var collected: CollectedComparison
  var prepared: PreparedSession
}

extension SessionWindowController {
  /// Opens a window for `collection`: the list of its files in the sidebar, once there are two
  /// or the collection compares folders, and the first file beside it, drawn and started as
  /// `settings` say.
  ///
  /// The window keeps showing files as the collection receives them. Before the first file of
  /// two folders is known, it says that it compares them, and shows the first file that differs
  /// once there is one.
  ///
  /// The window waits for the comparison of its first file as a window of one comparison does:
  /// one that is ready within ``comparisonWait`` fills the window before it shows; otherwise it
  /// shows with the headers of the file and empty panes, which fill once the file is compared.
  ///
  /// - Parameter patch: The copy of the patch whose files `collection` holds, if it holds the
  ///   files of a patch; it goes with the window.
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if not even the headers of the first file
  ///   can be made.
  public convenience init(
    collection: FileCollection, undoManager: UndoManager, settings: UserSettings,
    patch: PatchCopy? = nil
  ) async throws(SessionLoadingError) {
    let start = ContinuousClock.now
    let opening = try await Self.opening(collection, settings: settings, patch: patch)
    self.init(
      session: opening.session, context: opening.context, undoManager: undoManager,
      displayOptions: .current(in: .shared), pasteboard: .general,
      workspace: NSWorkspace.shared, prompts: SessionSheets(), doneStyle: .standard,
      settings: settings, syntaxChoices: .shared, window: SessionWindow(),
      collectionNavigator: opening.navigator, pendingFile: opening.comparison)
    observeDisplayOptions()
    await fillIfReady(
      opening, within: Self.comparisonWait - (ContinuousClock.now - start) / .seconds(1))
  }

  /// What a window of `collection` opens with: the headers of its first file that the list
  /// shows, and the comparison of that file in the comparison mode and with the ignore rules of
  /// `settings` begun away from the main actor; or the empty comparison of its two folders while
  /// no such file is known.
  ///
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if not even the headers can be made.
  static func opening(
    _ collection: FileCollection, settings: UserSettings, patch: PatchCopy? = nil
  ) async throws(SessionLoadingError) -> CollectionOpening {
    let navigator = CollectionNavigator(
      collection: collection, showsIdenticalFiles: settings.showsIdenticalFiles)
    navigator.listFiles()
    guard let file = navigator.listedIndices.first.map({ collection.files[$0] }) else {
      guard let folders = collection.folders else {
        preconditionFailure("A window of a collection needs a file to show")
      }
      return CollectionOpening(
        session: try await emptySession(of: folders), context: SessionContext(folders: folders),
        navigator: navigator)
    }
    let (mode, rules) = (settings.comparisonMode, settings.ignoreRules)
    // The comparison runs while the window is made, as that of a window of one comparison does.
    // It runs to its end even once the window shows another file or closed, since the engine
    // cannot stop midway; the window keeps what it finds, or drops it once closed.
    let comparison = PendingFile.detached(priority: .userInitiated) {
      do {
        return try await CollectedComparison(reading: file, mode: mode, ignoring: rules)
      } catch {
        Self.logger.error("Cannot show \(file.path, privacy: .public): \(error, privacy: .public)")
        return nil
      }
    }
    var difftool = file.difftool
    difftool.filePosition = FilePosition(
      number: 1, count: max(collection.expectedCount ?? 0, navigator.listedIndices.count))
    return CollectionOpening(
      session: try await emptySession(
        of: Session.Inputs(a: file.old, b: file.new), kind: .diff, mode: mode),
      context: SessionContext(difftool: difftool, folders: collection.namingFolders, patch: patch),
      comparison: comparison, navigator: navigator)
  }

  /// Fills the window, which waits for the comparison of the first file of `opening`, before it
  /// shows if the comparison is there within `wait` seconds.
  func fillIfReady(_ opening: CollectionOpening, within wait: TimeInterval) async {
    guard let comparison = opening.comparison, wait > 0,
      await Self.outcome(of: comparison, within: wait) != nil
    else { return }
    await phase.filling?.value
  }

  /// Shows the file after the one in view in the list.
  @objc func showNextFile(_ sender: Any?) {
    guard canPerform(.nextFile), let index = collectionNavigator?.neighborIndex(forward: true)
    else { return }
    showFile(at: index)
  }

  /// Shows the file before the one in view in the list.
  @objc func showPreviousFile(_ sender: Any?) {
    guard canPerform(.previousFile),
      let index = collectionNavigator?.neighborIndex(forward: false)
    else { return }
    showFile(at: index)
  }

  /// Lists the files of two folders that hold the same bytes as well, or leaves them out, and
  /// remembers the choice for the next such window.
  @objc func toggleIdenticalFiles(_ sender: Any?) {
    guard canPerform(.toggleIdenticalFiles), let collectionNavigator else { return }
    collectionNavigator.changeFilter { $0.showsIdenticalFiles.toggle() }
    settings.showsIdenticalFiles = collectionNavigator.filter.showsIdenticalFiles
    showList(scrolling: true)
  }

  /// Puts the focus into the field that filters the list, and shows the list if it is hidden.
  @objc func filterFiles(_ sender: Any?) {
    guard canPerform(.filterFiles), let collectionLayout else { return }
    if collectionLayout.sidebarItem.isCollapsed {
      collectionLayout.toggleSidebar(sender)
    }
    window?.makeFirstResponder(collectionLayout.fileList.filterField)
  }

  /// Shows the file at `index` of the collection, once it is read, where the window left it, or
  /// at its first change; the focus stays where it is.
  func showFile(at index: Int) {
    guard let collectionNavigator, collectionNavigator.canGo(toFileAt: index) else { return }
    keepShownFile()
    let file = collectionNavigator.go(toFileAt: index)
    markChangedFilesInTheList()
    collectionLayout?.fileList.select(index)
    load(file)
  }

  /// Reads `file`, the file the window is about to show, or waits for its `comparison` that
  /// runs already, makes its panes away from the main actor and shows it.
  ///
  /// A file that is not ready within ``fileWait`` shows its headers and empty panes
  /// meanwhile, as a window of one comparison that opens does; one with a `comparison` does so
  /// at once, since the window opened with them. Another file to show, or closing the window,
  /// cancels the reading: the comparison under way runs to its end, but neither shows nor is
  /// made ready for the panes.
  private func load(_ file: CollectedFile, comparing comparison: PendingFile? = nil) {
    fileLoad?.cancel()
    let ready = readying(file, comparing: comparison)
    let filling = comparison.map { _ in fill(from: ready, of: file) }
    fileLoad = Task { [weak self] in
      await withTaskCancellationHandler {
        if let filling {
          await filling.value
        } else {
          await self?.show(from: ready, of: file)
        }
      } onCancel: {
        ready.cancel()
      }
      guard !Task.isCancelled else { return }
      await self?.readAhead(after: file)
    }
    if let filling {
      beginWaiting(filling: filling)
    }
  }

  /// Reads `file`, or waits for its `comparison`, and makes its panes away from the main actor;
  /// `nil` if it cannot even be shown as a file that cannot be compared, or the reading was
  /// cancelled.
  private func readying(
    _ file: CollectedFile, comparing comparison: PendingFile?
  ) -> Task<ReadyFile?, Never> {
    let generation = collectionNavigator?.diskGeneration
    return Task { [weak self] in
      let collected: CollectedComparison?
      if let comparison {
        collected = await comparison.value
        if let collected, let generation, let self, !hasFinished {
          collectionNavigator?.keep(collected, of: file, readIn: generation)
        }
      } else {
        collected = await self?.collectedComparison(of: file)
      }
      guard let self, let collected, !Task.isCancelled, !hasFinished else { return nil }
      return ReadyFile(
        collected: collected, prepared: await presentation.prepareLoaded(collected.session))
    }
  }

  /// Shows `file` once `ready` has it: at once if that is within ``fileWait``, otherwise after
  /// waiting for it with the headers of the file and empty panes.
  private func show(from ready: Task<ReadyFile?, Never>, of file: CollectedFile) async {
    if fileWait > 0, let outcome = await Self.outcome(of: ready, within: fileWait) {
      await show(outcome, of: file, from: ready)
      return
    }
    guard await showWithoutLines(file), !ready.isCancelled else { return }
    let filling = fill(from: ready, of: file)
    beginWaiting(filling: filling)
    await filling.value
  }

  /// Fills the panes, which wait with the headers of `file`, once `ready` has it.
  private func fill(from ready: Task<ReadyFile?, Never>, of file: CollectedFile) -> Task<
    Void, Never
  > {
    Task { [weak self] in
      await self?.show(await ready.value, of: file, from: ready)
    }
  }

  /// Shows `outcome`, which `ready` had for `file`, with its panes made for the setup they have
  /// now, which may have changed since, as the headers of the file showed meanwhile; shows
  /// nothing once the window shows another file or closed.
  private func show(
    _ outcome: ReadyFile?, of file: CollectedFile, from ready: Task<ReadyFile?, Never>
  ) async {
    var outcome = outcome
    if let made = outcome, made.prepared.setup != presentation.setup {
      outcome = ReadyFile(
        collected: made.collected,
        prepared: await presentation.prepareLoaded(made.collected.session))
    }
    guard !ready.isCancelled, collectionNavigator?.shows(file) == true, !hasFinished else {
      return
    }
    show(outcome, of: file)
  }

  /// Shows the headers of `file` above empty panes in place of the file in view, while it is
  /// read; tells whether it did, which it does not once the window shows another file or closed.
  private func showWithoutLines(_ file: CollectedFile) async -> Bool {
    guard
      let empty = try? await Self.emptySession(
        of: Session.Inputs(a: file.old, b: file.new), kind: .diff, mode: comparisonOptions.mode)
    else { return false }
    let prepared = await presentation.prepareLoaded(empty)
    guard !Task.isCancelled, collectionNavigator?.shows(file) == true, !hasFinished else {
      return false
    }
    showsHeadersOnly = true
    show(
      CollectedComparison(session: empty, unavailable: nil), prepared: prepared, of: file,
      placing: false)
    return true
  }

  /// Shows `ready`, the file in view ready to show, or, for `nil`, that it cannot be shown; a
  /// window that waited for it lets the lines fade in, does what it put off meanwhile, and tells
  /// VoiceOver once it shows.
  private func show(_ ready: ReadyFile?, of file: CollectedFile) {
    let waited = waitsForComparison
    if waited {
      endWaiting()
    }
    guard let ready else {
      guard waited else { return }
      // The headers of the file stand above empty panes; they say why they stay empty.
      let comparison = UnavailableComparison(
        old: file.old, new: file.new, reason: .comparisonFailed)
      phase = .unavailable(comparison)
      layout.showInPlaceOfTheLines(
        UnavailableComparisonView(
          title: comparison.title, message: comparison.message(in: SessionContext())))
      sessionDidChange()
      stateDidChange()
      return
    }
    if waited {
      fadeInTheLines()
    }
    showsHeadersOnly = false
    show(ready.collected, prepared: ready.prepared, of: file)
    guard waited else { return }
    diskWatch.lookAgainIfAsked()
    followIgnoreRules()
    guard window?.isVisible == true else { return }
    presentation.announce(phase.unavailable?.title ?? comparedAnnouncement)
  }

  /// Sets up the list of the files and follows the collection as it receives more; the window
  /// shows the file whose `comparison` runs once it is there.
  func setUpCollection(comparingFirstFile comparison: PendingFile?) {
    guard let collectionNavigator, let collectionLayout else { return }
    let collection = collectionNavigator.collection
    // Files may have come while the window was made, some of them before the first.
    if let path = context.difftool?.path,
      let index = collection.files.firstIndex(where: { $0.path == path })
    {
      let file = collectionNavigator.go(toFileAt: index)
      if let comparison {
        load(file, comparing: comparison)
      } else {
        collectionNavigator.keep(
          CollectedComparison(
            session: presentation.changes.session, unavailable: phase.unavailable),
          of: file, readIn: collectionNavigator.diskGeneration)
      }
    } else {
      // Files only come; the one whose comparison the window opened with is among them.
      assert(comparison == nil, "The first file of a collection stays in it")
    }
    collectionLayout.fileList.delegate = self
    collectionLayout.sidebarDidChange = { [weak self] in self?.updateMinimumSize() }
    collection.onChange = { [weak self] change in self?.collectionDidChange(change) }
    listFiles(scrolling: true)
    showStatus()
  }

  private func collectionDidChange(_ change: FileCollection.Change) {
    guard let collectionNavigator else { return }
    let collection = collectionNavigator.collection
    switch change {
    case .inserted(let index):
      collectionNavigator.fileWasInserted(at: index)
    case .updated:
      if !collection.isReceiving {
        // The window watches the file in view itself.
        collectionNavigator.filesChangedOnDisk()
      }
      followShownFile()
    case .complete:
      if let summary = differingSummary {
        presentation.announce(summary)
      } else if collection.files.count > 1 {
        presentation.announce(FileListViewController.receivedText(collection.files.count))
      }
    }
    if collectionNavigator.forgetChangesOfFilesNoLongerCompared() {
      markChangedFilesInTheList()
    }
    listFiles(scrolling: false)
    showStatus()
  }

  /// Finds the file in view again after the files of folders changed: reads it anew if its sides
  /// changed or it became readable or unreadable, and shows the next file of the list in its
  /// place if it went.
  private func followShownFile() {
    guard let collectionNavigator else { return }
    switch collectionNavigator.followShownFile() {
    case .stays:
      return
    case .readsAnew(let file):
      // Changes kept of sides that are other files now go as the window looks at the changes
      // of the folders next.
      keepShownFile()
      load(file)
    case .went(let next):
      // The next file in the order takes its place. The list in view follows after it, as for
      // every change of the files: shown with no file in view, it would show its first.
      collectionNavigator.listFiles()
      if let index = collectionNavigator.listedIndex(from: next) {
        showFile(at: index)
      }
    }
  }

  /// Lists the files that the filter lets through as the collection holds them now, and shows
  /// the list; with `scrolling`, the selected row comes into view.
  private func listFiles(scrolling: Bool) {
    collectionNavigator?.listFiles()
    showList(scrolling: scrolling)
  }

  /// Shows the files that the navigator lists, keeps the file in view selected if the list
  /// shows it, and shows the first file of two folders once the list has one; with `scrolling`,
  /// the selected row comes into view.
  private func showList(scrolling: Bool) {
    guard let collectionNavigator, let collectionLayout else { return }
    let collection = collectionNavigator.collection
    collectionLayout.fileList.show(
      collectionNavigator.listedGroups, of: collection.files,
      selecting: collectionNavigator.shownFile.map { _ in collectionNavigator.fileIndex },
      scrolling: scrolling)
    let hasList = collection.folders != nil || collection.files.count > 1
    collectionLayout.hasList = hasList
    toolbar.showsSidebarButton(hasList)
    if collectionNavigator.shownFile == nil, let first = collectionNavigator.listedIndices.first {
      showFile(at: first)
      presentation.announce(
        collection.files[first].change.presentation.toolTip(
          for: collection.files[first].path))
    }
    showPlaceholderIfNeeded()
    context.difftool?.filePosition = collectionNavigator.filePosition
    sessionDidChange()
    stateDidChange()
  }

  /// Says in place of the lines why no file of two folders is shown, while none is.
  private func showPlaceholderIfNeeded() {
    guard let collectionNavigator, collectionNavigator.shownFile == nil else { return }
    let collection = collectionNavigator.collection
    let placeholder: CollectionPlaceholder =
      if collection.isReceiving {
        .comparing
      } else if collection.files.allSatisfy({ $0.change == .identical }) {
        .sameFiles
      } else {
        .noFile
      }
    guard placeholder != phase.placeholder else { return }
    if waitsForComparison {
      // The file the window waited for went from the folders; there is nothing left to wait for.
      endWaiting()
    }
    phase = .placeholder(placeholder)
    layout.showInPlaceOfTheLines(
      UnavailableComparisonView(title: placeholder.title, message: placeholder.message))
  }

  /// Shows below the list how many files have come while more come, how far the comparison of
  /// two folders is, or what it found.
  private func showStatus() {
    guard let collection, let fileList = collectionLayout?.fileList else { return }
    if collection.folders != nil {
      fileList.showStatus(
        differingSummary
          ?? FileListViewController.comparingText(
            collection.comparedCount, of: collection.pairedCount),
        isBusy: collection.isReceiving)
    } else {
      fileList.showStatus(
        collection.isReceiving
          ? FileListViewController.receivingText(
            collection.files.count, of: collection.expectedCount) : nil,
        isBusy: true)
    }
  }

  /// How many files of two compared folders differ, once they are compared.
  private var differingSummary: String? {
    guard let collection, collection.folders != nil, !collection.isReceiving else { return nil }
    let differing = collection.files.count { file in
      [.modified, .added, .deleted].contains(file.change)
    }
    return FileListViewController.differingText(differing, of: collection.files.count)
  }

  /// Shows `collected`, the comparison of `file` whose panes show `prepared`, in place of the file
  /// in view; with `placing`, where the window left the file, or at its first change.
  private func show(
    _ collected: CollectedComparison, prepared: PreparedSession, of file: CollectedFile,
    placing: Bool = true
  ) {
    guard let collectionNavigator else { return }
    comparisonSwitcher.stopBringingBack()
    var difftool = file.difftool
    difftool.filePosition = collectionNavigator.filePosition
    context = SessionContext(
      difftool: difftool, folders: collectionNavigator.collection.namingFolders,
      patch: context.patch)
    let session = collected.session
    phase = collected.unavailable.map(SessionPhase.unavailable) ?? .ready
    if placing {
      takeFiles(of: collected)
    }
    if let unavailable = collected.unavailable {
      layout.showInPlaceOfTheLines(
        UnavailableComparisonView(
          title: unavailable.title, message: unavailable.message(in: SessionContext())))
    } else {
      layout.showLinesAgain()
    }
    resultUndo.endTypingRun()
    presentation.showOtherFiles(prepared)
    presentation.show(SideHeader.headers(of: session, context: context))
    detectedLanguage = SessionSyntax.language(of: session, context: SessionContext())
    syntaxPath = SessionSyntax.path(of: session, context: SessionContext())
    presentation.colorSyntax(as: syntaxLanguage)
    sessionUndoManager.removeAllActions()
    comparisonSwitcher.forgetShownBefore()
    sessionDidChange()
    watchFiles()
    if let readSince = collected.readSince {
      diskWatch.lookIfModified(since: readSince)
    }
    if placing {
      restorePlace(of: file)
    }
    window?.representedURL = editableFileURL
    if collected.unavailable != nil, let window,
      layout.sourcePanes.contains(where: { window.firstResponder === $0.pane.documentView })
    {
      // The panes are hidden; the list is the closest place for the focus to stay.
      window.makeFirstResponder(collectionLayout?.fileList.tableView)
    }
    stateDidChange()
  }

  /// Keeps the place in the file in view and its copied changes, as the window is about to show
  /// another file or to read it anew; a window that waits for the file has neither yet, and the
  /// navigator still keeps the changes it waits to show.
  private func keepShownFile() {
    guard let collectionNavigator, collectionNavigator.shownFile != nil, !waitsForComparison,
      !showsHeadersOnly
    else { return }
    collectionNavigator.keepPlace(currentPlace)
    if case .ready = phase {
      collectionNavigator.keepChanges(shownChanges)
    }
  }

  /// Takes the files of `collected`, the file in view about to show: its copied changes, which
  /// the window holds itself from now on; else the files as read, whose bytes on disk the window
  /// need not keep until a copy changes them, nor of the files it showed before.
  private func takeFiles(of collected: CollectedComparison) {
    guard let collectionNavigator, let shown = collectionNavigator.shownFile else { return }
    if collectionNavigator.changedFiles[shown.path] != nil {
      collectionNavigator.takeChangesOfShownFile()
      // Another app may have written the files meanwhile, which the window did not watch.
      diskWatch.filesMayHaveChanged()
    } else {
      filesOnDisk.forget(collected.session.inputs.values)
    }
  }

  /// The place the window shows now: the current block and the row at the reading line.
  private var currentPlace: FilePlace {
    let place = presentation.leadingPane?.rowAtReadingLine ?? (row: 0, fraction: 0)
    return FilePlace(
      currentBlock: presentation.currentBlock, row: place.row, fraction: place.fraction,
      lineArrangement: presentation.lineArrangement)
  }

  /// Shows `file` where the window left it, or from its top at its first change.
  ///
  /// The file may have fewer changes than when the window left it, as after another comparison
  /// mode; the current change is then its last.
  private func restorePlace(of file: CollectedFile) {
    guard let pane = presentation.leadingPane ?? layout.sourcePanes.first?.pane else { return }
    guard let place = collectionNavigator?.place(of: file) else {
      presentation.setCurrentBlock(presentation.navigation.firstChange)
      presentation.showCurrentBlock()
      return
    }
    let lastBlock = presentation.changes.blocks.indices.last
    presentation.setCurrentBlock(
      place.currentBlock.flatMap { block in lastBlock.map { min(block, $0) } })
    guard place.lineArrangement == presentation.lineArrangement else {
      // The row counts otherwise since the arrangement changed; the current block stays in view.
      presentation.showCurrentBlock()
      return
    }
    pane.scroll(toPlaceRowAtReadingLine: place.row, fraction: place.fraction, motion: .cut)
  }

  /// The comparison of `file` in the comparison mode and with the ignore rules of the window,
  /// from those read already or read now; `nil` if it cannot even be shown as a file that cannot
  /// be compared.
  private func collectedComparison(of file: CollectedFile) async -> CollectedComparison? {
    await collectionNavigator?.comparison(
      of: file, mode: comparisonOptions.mode, ignoring: requestedIgnoreRules)
  }

  /// Reads the file after `file` in the list ahead in the comparison mode and with the ignore
  /// rules of the window.
  private func readAhead(after file: CollectedFile) async {
    await collectionNavigator?.readAhead(
      after: file, mode: comparisonOptions.mode, ignoring: requestedIgnoreRules)
  }

  /// The empty comparison of `folders`, which gives the window its headers before it shows a
  /// file of them.
  ///
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if even that fails.
  private static func emptySession(of folders: FolderPair) async throws(SessionLoadingError)
    -> Session
  {
    let names = folders.distinctNames
    do {
      return try await Session.diff(
        old: SourceFile(bytes: Data(), label: names.left),
        new: SourceFile(bytes: Data(), label: names.right),
        mode: .windowDefault)
    } catch {
      throw .comparisonFailed
    }
  }
}

extension SessionWindowController: FileListDelegate {
  func fileList(_ fileList: FileListViewController, didSelectFileAt index: Int) {
    showFile(at: index)
  }

  func fileList(_ fileList: FileListViewController, didChangeFilter text: String) {
    collectionNavigator?.changeFilter { $0.text = text }
    showList(scrolling: true)
  }
}
