public import AppKit
import GitSupport
import MergeModel
import PaneKit
import TextBasics
import os

/// The place in a file that a window that compares several files keeps while it shows another.
struct FilePlace: Equatable {
  /// The current block.
  var currentBlock: Int?

  /// The row at the reading line of the panes, and how far into it the line falls.
  var row: Int
  var fraction: CGFloat

  /// How the panes laid out the lines, which tells what the row counts: a row of the grid, a
  /// line of the left file, or a row of the single column.
  var lineArrangement: LineArrangement
}

/// A file of a collection as the window read it: its comparison, or the empty one of a file it
/// cannot compare, with the reason.
struct CollectedComparison {
  var session: Session
  var unavailable: UnavailableComparison?
}

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
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if not even the headers of the first file
  ///   can be made.
  public convenience init(
    collection: FileCollection, undoManager: UndoManager, settings: UserSettings
  ) async throws(SessionLoadingError) {
    let start = ContinuousClock.now
    let opening = try await Self.opening(collection, settings: settings)
    self.init(
      session: opening.session, context: opening.context, undoManager: undoManager,
      displayOptions: .current(in: .shared), pasteboard: .general,
      workspace: NSWorkspace.shared, prompts: SessionSheets(), doneStyle: .standard,
      settings: settings, syntaxChoices: .shared, window: SessionWindow(),
      collection: collection, pendingFile: opening.comparison)
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
    _ collection: FileCollection, settings: UserSettings
  ) async throws(SessionLoadingError) -> CollectionOpening {
    let filter = FileFilter(showsIdenticalFiles: settings.showsIdenticalFiles)
    let listed = collection.files.filter(filter.includes)
    guard let file = listed.first else {
      guard let folders = collection.folders else {
        preconditionFailure("A window of a collection needs a file to show")
      }
      return CollectionOpening(
        session: try await emptySession(of: folders), context: SessionContext(folders: folders))
    }
    let (mode, rules) = (settings.comparisonMode, settings.ignoreRules)
    // The comparison runs while the window is made, as that of a window of one comparison does.
    // It runs to its end even once the window shows another file or closed, since the engine
    // cannot stop midway; the window keeps what it finds, or drops it once closed.
    let comparison = PendingFile.detached(priority: .userInitiated) {
      do {
        return try await Self.load(file, mode: mode, ignoring: rules)
      } catch {
        Self.logger.error("Cannot show \(file.path, privacy: .public): \(error, privacy: .public)")
        return nil
      }
    }
    var difftool = file.difftool
    difftool.filePosition = FilePosition(
      number: 1, count: max(collection.expectedCount ?? 0, listed.count))
    return CollectionOpening(
      session: try await emptySession(
        of: Session.Inputs(a: file.old, b: file.new), kind: .diff, mode: mode),
      context: SessionContext(difftool: difftool, folders: collection.namingFolders),
      comparison: comparison)
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
    guard canPerform(.nextFile), let index = neighborIndex(forward: true) else { return }
    showFile(at: index)
  }

  /// Shows the file before the one in view in the list.
  @objc func showPreviousFile(_ sender: Any?) {
    guard canPerform(.previousFile), let index = neighborIndex(forward: false) else { return }
    showFile(at: index)
  }

  /// Lists the files of two folders that hold the same bytes as well, or leaves them out, and
  /// remembers the choice for the next such window.
  @objc func toggleIdenticalFiles(_ sender: Any?) {
    guard canPerform(.toggleIdenticalFiles) else { return }
    fileFilter.showsIdenticalFiles.toggle()
    settings.showsIdenticalFiles = fileFilter.showsIdenticalFiles
    listFiles(scrolling: true)
  }

  /// Puts the focus into the field that filters the list, and shows the list if it is hidden.
  @objc func filterFiles(_ sender: Any?) {
    guard canPerform(.filterFiles), let collectionLayout else { return }
    if collectionLayout.sidebarItem.isCollapsed {
      collectionLayout.toggleSidebar(sender)
    }
    window?.makeFirstResponder(collectionLayout.fileList.filterField)
  }

  /// The index in the collection of the file that Next File, or Previous File if not `forward`,
  /// shows: the next one the list shows after the file in view, wherever that file stands in
  /// the order, even if the list leaves it out.
  func neighborIndex(forward: Bool) -> Int? {
    guard shownFile != nil else { return nil }
    let row = listedIndices.partitioningIndex { $0 >= fileIndex }
    if forward {
      let next =
        listedIndices.indices.contains(row) && listedIndices[row] == fileIndex ? row + 1 : row
      return listedIndices.indices.contains(next) ? listedIndices[next] : nil
    }
    return row > 0 ? listedIndices[row - 1] : nil
  }

  /// Shows the file at `index` of the collection, once it is read, where the window left it, or
  /// at its first change; the focus stays where it is.
  func showFile(at index: Int) {
    guard let collection, collection.files.indices.contains(index),
      index != fileIndex || shownFile == nil
    else { return }
    if let shownFile, !waitsForComparison {
      filePlaces[shownFile.path] = currentPlace
    }
    let file = collection.files[index]
    fileIndex = index
    shownFile = file
    collectionLayout?.fileList.select(listedRow(of: index))
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
    let generation = diskGeneration
    return Task { [weak self] in
      let collected: CollectedComparison?
      if let comparison {
        collected = await comparison.value
        if let collected, let self, !hasFinished {
          keep(collected, of: file, readIn: generation)
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
    guard !ready.isCancelled, shownFile == file, !hasFinished else { return }
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
    guard !Task.isCancelled, shownFile == file, !hasFinished else { return false }
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
    guard let collection, let collectionLayout else { return }
    fileFilter.showsIdenticalFiles = settings.showsIdenticalFiles
    // Files may have come while the window was made, some of them before the first.
    if let path = context.difftool?.path,
      let index = collection.files.firstIndex(where: { $0.path == path })
    {
      fileIndex = index
      shownFile = collection.files[index]
      if let comparison {
        load(collection.files[index], comparing: comparison)
      } else {
        collectedComparisons[collection.files[index]] = CollectedComparison(
          session: presentation.changes.session, unavailable: phase.unavailable)
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
    guard let collection else { return }
    switch change {
    case .inserted(let index):
      if shownFile != nil, index <= fileIndex, collection.files.count > 1 {
        fileIndex += 1
      }
    case .updated:
      if !collection.isReceiving {
        // Files changed on disk; those read ahead may be out of date even where their entry in
        // the list reads the same. The window watches the file in view itself.
        collectedComparisons = collectedComparisons.filter { $0.key == shownFile }
        diskGeneration += 1
      }
      followShownFile()
    case .complete:
      if let summary = differingSummary {
        presentation.announce(summary)
      } else if collection.files.count > 1 {
        presentation.announce(FileListViewController.receivedText(collection.files.count))
      }
    }
    listFiles(scrolling: false)
    showStatus()
  }

  /// Finds the file in view again after the files of folders changed: reads it anew if its sides
  /// changed or it became readable or unreadable, and shows the next file of the list in its
  /// place if it went.
  ///
  /// A change of the bytes of the file in view, the window reloads by itself as it watches the
  /// file.
  private func followShownFile() {
    guard let collection, let shown = shownFile else { return }
    if let index = collection.files.firstIndex(where: { $0.path == shown.path }) {
      fileIndex = index
      let file = collection.files[index]
      shownFile = file
      let isUnreadable = { (file: CollectedFile) in
        if case .unreadable = file.change { true } else { false }
      }
      if file.old.url != shown.old.url || file.new.url != shown.new.url
        || isUnreadable(file) != isUnreadable(shown)
      {
        // A window that waits for the file has no place in it yet.
        if !waitsForComparison {
          filePlaces[file.path] = currentPlace
        }
        load(file)
      }
      return
    }
    // The file went from both folders; the next file in the order takes its place.
    let next = collection.files.firstIndex { !$0.precedes(shown) }
    shownFile = nil
    fileIndex = 0
    listFiles(scrolling: false)
    let index =
      next.flatMap { next in listedIndices.first { $0 >= next } } ?? listedIndices.last
    if let index {
      showFile(at: index)
    }
  }

  /// Lists the files that the filter lets through, keeps the file in view selected if the list
  /// shows it, and shows the first file of two folders once the list has one; with `scrolling`,
  /// the selected row comes into view.
  func listFiles(scrolling: Bool) {
    guard let collection, let collectionLayout else { return }
    let filter = fileFilter
    listedIndices = collection.files.indices.filter { filter.includes(collection.files[$0]) }
    collectionLayout.fileList.show(
      listedIndices.map { collection.files[$0] },
      selecting: shownFile.flatMap { _ in
        listedRow(of: fileIndex)
      }, scrolling: scrolling)
    let hasList = collection.folders != nil || collection.files.count > 1
    collectionLayout.hasList = hasList
    toolbar.showsSidebarButton(hasList)
    if shownFile == nil, let first = listedIndices.first {
      showFile(at: first)
      presentation.announce(
        collection.files[first].change.presentation.toolTip(
          for: collection.files[first].path))
    }
    showPlaceholderIfNeeded()
    context.difftool?.filePosition = filePosition
    sessionDidChange()
    stateDidChange()
  }

  /// The row of the list that shows the file at `index` of the collection, if the list shows it.
  func listedRow(of index: Int) -> Int? {
    let row = listedIndices.partitioningIndex { $0 >= index }
    return listedIndices.indices.contains(row) && listedIndices[row] == index ? row : nil
  }

  /// Where the file in view stands in the list: among as many files as Git announced or the list
  /// holds, while nothing is typed in the filter field; `nil` if the list leaves the file out.
  private var filePosition: FilePosition? {
    guard shownFile != nil, let row = listedRow(of: fileIndex) else { return nil }
    let count =
      fileFilter.text.isEmpty
      ? max(collection?.expectedCount ?? 0, listedIndices.count) : listedIndices.count
    return FilePosition(number: row + 1, count: count)
  }

  /// Says in place of the lines why no file of two folders is shown, while none is.
  private func showPlaceholderIfNeeded() {
    guard let collection, shownFile == nil else { return }
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
    guard collection != nil else { return }
    stopBringingBack()
    var difftool = file.difftool
    difftool.filePosition = filePosition
    context = SessionContext(difftool: difftool, folders: collection?.namingFolders)
    let session = collected.session
    phase = collected.unavailable.map(SessionPhase.unavailable) ?? .ready
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
    detectedLanguage = SessionSyntax.language(of: session, resultURL: nil)
    syntaxPath = SessionSyntax.path(of: session, resultURL: nil)
    presentation.colorSyntax(as: syntaxLanguage)
    sessionUndoManager.removeAllActions()
    comparisonShownBefore = nil
    sessionDidChange()
    watchFiles()
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

  /// The place the window shows now: the current block and the row at the reading line.
  private var currentPlace: FilePlace {
    let place = presentation.leadingPane?.rowAtReadingLine ?? (row: 0, fraction: 0)
    return FilePlace(
      currentBlock: presentation.currentBlock, row: place.row, fraction: place.fraction,
      lineArrangement: presentation.lineArrangement)
  }

  /// Shows `file` where the window left it, or from its top at its first change.
  private func restorePlace(of file: CollectedFile) {
    guard let pane = presentation.leadingPane ?? layout.sourcePanes.first?.pane else { return }
    guard let place = filePlaces[file.path] else {
      presentation.setCurrentBlock(presentation.navigation.firstChange)
      presentation.showCurrentBlock()
      return
    }
    presentation.setCurrentBlock(place.currentBlock)
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
    let mode = comparisonOptions.mode
    let rules = requestedIgnoreRules
    if let collected = collectedComparisons[file], collected.session.options.mode == mode,
      collected.unavailable != nil || Self.haveTheSameEffect(collected.session.ignoreRules, rules)
    {
      return collected
    }
    let generation = diskGeneration
    do {
      let collected = try await Self.load(file, mode: mode, ignoring: rules)
      keep(collected, of: file, readIn: generation)
      return collected
    } catch {
      Self.logger.error("Cannot show \(file.path, privacy: .public): \(error, privacy: .public)")
      return nil
    }
  }

  /// Keeps `collected`, the comparison of `file` read since the change on disk of `generation`,
  /// unless the files changed on disk again meanwhile.
  func keep(_ collected: CollectedComparison, of file: CollectedFile, readIn generation: Int) {
    guard generation == diskGeneration else { return }
    collectedComparisons[file] = collected
  }

  /// Reads the file after `file` in the list ahead, and forgets the files that are not beside
  /// the one in view.
  private func readAhead(after file: CollectedFile) async {
    guard let collection else { return }
    let next = neighborIndex(forward: true)
    let neighbors = [neighborIndex(forward: false), fileIndex, next].compactMap(\.self)
    let kept = Set(neighbors.map { collection.files[$0] })
    collectedComparisons = collectedComparisons.filter { kept.contains($0.key) }
    if let next {
      _ = await collectedComparison(of: collection.files[next])
    }
  }

  /// Reads both sides of `file` and compares them in `mode` without the text that the enabled
  /// rules of `rules` match; a file that cannot be compared,
  /// such as an image, gets an empty comparison that names it, and the reason.
  ///
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if not even the empty comparison can be
  ///   made.
  static func load(
    _ file: CollectedFile, mode: ComparisonMode, ignoring rules: [IgnoreRule]
  ) async throws(SessionLoadingError) -> CollectedComparison {
    do {
      return CollectedComparison(
        session: try await Session.loadDiff(
          old: file.old, new: file.new, mode: mode, ignoring: rules),
        unavailable: nil)
    } catch {
      let unavailable = UnavailableComparison(old: file.old, new: file.new, reason: error)
      return CollectedComparison(
        session: try await unavailable.emptySession(), unavailable: unavailable)
    }
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
  func fileList(_ fileList: FileListViewController, didSelectRow row: Int) {
    guard listedIndices.indices.contains(row) else { return }
    showFile(at: listedIndices[row])
  }

  func fileList(_ fileList: FileListViewController, didChangeFilter text: String) {
    fileFilter.text = text
    listFiles(scrolling: true)
  }
}
