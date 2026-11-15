import AppKit
import GitSupport
import MergeModel

/// The place in a file that a window that compares several files keeps while it shows another.
struct FilePlace: Equatable {
  /// The current block.
  var currentBlock: Int?

  /// The row at the reading line of the panes, and how far into it the line falls.
  var row: Int
  var fraction: CGFloat

  /// Whether the panes lined up their lines, so that the row is one of the grid, or else
  /// showed the lines of their files, so that it is a line of the left one.
  var alignsLines: Bool
}

/// A file of a collection as the window read it: its comparison, or the empty one of a file it
/// cannot compare, with the reason.
struct LoadedFile {
  var session: Session
  var unavailable: UnavailableComparison?
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
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if not even the headers of the first file
  ///   can be made.
  public convenience init(
    collection: FileCollection, undoManager: UndoManager, settings: UserSettings
  ) async throws(SessionLoadingError) {
    let opening = try await Self.opening(collection, settings: settings)
    self.init(
      session: opening.loaded.session, context: opening.context, undoManager: undoManager,
      displayOptions: .current(in: .shared), pasteboard: .general,
      workspace: NSWorkspace.shared, prompts: SessionSheets(), doneStyle: .standard,
      settings: settings, syntaxChoices: .shared, window: SessionWindow(),
      unavailable: opening.loaded.unavailable, collection: collection)
    observeDisplayOptions()
  }

  /// What a window of `collection` opens with: its first file that the list shows, read in the
  /// comparison mode and with the ignore rules of `settings`, or the empty comparison of its two
  /// folders while no such file is known.
  ///
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if not even the headers can be made.
  static func opening(
    _ collection: FileCollection, settings: UserSettings
  ) async throws(SessionLoadingError) -> (loaded: LoadedFile, context: SessionContext) {
    let filter = FileFilter(showsIdenticalFiles: settings.showsIdenticalFiles)
    let listed = collection.files.filter(filter.includes)
    guard let file = listed.first else {
      guard let folders = collection.folders else {
        preconditionFailure("A window of a collection needs a file to show")
      }
      return (
        LoadedFile(session: try await emptySession(of: folders), unavailable: nil),
        SessionContext(folders: folders)
      )
    }
    var difftool = file.difftool
    difftool.filePosition = FilePosition(
      number: 1, count: max(collection.expectedCount ?? 0, listed.count))
    return (
      try await load(file, mode: settings.comparisonMode, ignoring: settings.ignoreRules),
      SessionContext(difftool: difftool, folders: collection.folders)
    )
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
    if let shownFile {
      filePlaces[shownFile.path] = currentPlace
    }
    let file = collection.files[index]
    fileIndex = index
    shownFile = file
    collectionLayout?.fileList.select(listedRow(of: index))
    load(file)
  }

  /// Reads `file`, the file the window is about to show, and shows it.
  private func load(_ file: CollectedFile) {
    fileLoad?.cancel()
    fileLoad = Task { [weak self] in
      guard let self, let loaded = await self.loaded(file), !Task.isCancelled,
        shownFile == file
      else { return }
      show(loaded, of: file)
      await readAhead(after: file)
    }
  }

  /// Sets up the list of the files and follows the collection as it receives more.
  func setUpCollection() {
    guard let collection, let collectionLayout else { return }
    fileFilter.showsIdenticalFiles = settings.showsIdenticalFiles
    // Files may have come while the window read the first one, some of them before it.
    if let path = context.difftool?.path,
      let index = collection.files.firstIndex(where: { $0.path == path })
    {
      fileIndex = index
      shownFile = collection.files[index]
      loadedFiles[collection.files[index]] = LoadedFile(
        session: presentation.changes.session, unavailable: unavailable)
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
        loadedFiles = loadedFiles.filter { $0.key == shownFile }
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
        filePlaces[file.path] = currentPlace
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
    guard placeholder != collectionPlaceholder else { return }
    collectionPlaceholder = placeholder
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

  /// Shows `loaded`, the comparison of `file`, in place of the file in view.
  private func show(_ loaded: LoadedFile, of file: CollectedFile) {
    guard collection != nil else { return }
    var difftool = file.difftool
    difftool.filePosition = filePosition
    context = SessionContext(difftool: difftool, folders: collection?.folders)
    let session = loaded.session
    unavailable = loaded.unavailable
    collectionPlaceholder = nil
    if let unavailable {
      layout.showInPlaceOfTheLines(
        UnavailableComparisonView(
          title: unavailable.title, message: unavailable.message(in: SessionContext())))
    } else {
      layout.showLinesAgain()
    }
    typingRun = nil
    presentation.showOtherFiles(session)
    presentation.show(
      Dictionary(
        uniqueKeysWithValues: session.roles.map { role in
          (role, SideHeader(role: role, session: session, context: context))
        }))
    detectedLanguage = SessionSyntax.language(of: session, resultURL: nil)
    syntaxPath = SessionSyntax.path(of: session, resultURL: nil)
    presentation.colorSyntax(as: syntaxLanguage)
    sessionUndoManager.removeAllActions()
    sessionDidChange()
    watchFiles()
    restorePlace(of: file)
    window?.representedURL = editableFileURL
    if unavailable != nil, let window,
      layout.sourcePanes.contains(where: { window.firstResponder === $0.pane.documentView })
    {
      // The panes are hidden; the list is the closest place for the focus to stay.
      window.makeFirstResponder(collectionLayout?.fileList.tableView)
    }
    stateDidChange()
  }

  /// The place the window shows now: the current block and the row at the reading line.
  private var currentPlace: FilePlace {
    let place = layout.sourcePanes.first?.pane.rowAtReadingLine ?? (row: 0, fraction: 0)
    return FilePlace(
      currentBlock: presentation.currentBlock, row: place.row, fraction: place.fraction,
      alignsLines: presentation.alignsLines)
  }

  /// Shows `file` where the window left it, or from its top at its first change.
  private func restorePlace(of file: CollectedFile) {
    guard let pane = layout.sourcePanes.first?.pane else { return }
    guard let place = filePlaces[file.path] else {
      presentation.setCurrentBlock(presentation.navigation.firstChange)
      presentation.showCurrentBlock()
      return
    }
    presentation.setCurrentBlock(place.currentBlock)
    guard place.alignsLines == presentation.alignsLines else {
      // The row counts otherwise since Align Lines changed; the current block stays in view.
      presentation.showCurrentBlock()
      return
    }
    pane.scroll(toPlaceRowAtReadingLine: place.row, fraction: place.fraction, motion: .cut)
  }

  /// The comparison of `file` in the comparison mode and with the ignore rules of the window,
  /// from those read already or read now; `nil` if it cannot even be shown as a file that cannot
  /// be compared.
  private func loaded(_ file: CollectedFile) async -> LoadedFile? {
    let mode = comparisonOptions.mode
    let rules = requestedIgnoreRules
    if let loaded = loadedFiles[file], loaded.session.options.mode == mode,
      loaded.unavailable != nil || Self.haveTheSameEffect(loaded.session.ignoreRules, rules)
    {
      return loaded
    }
    let generation = diskGeneration
    do {
      let loaded = try await Self.load(file, mode: mode, ignoring: rules)
      keep(loaded, of: file, readIn: generation)
      return loaded
    } catch {
      Self.logger.error("Cannot show \(file.path, privacy: .public): \(error, privacy: .public)")
      return nil
    }
  }

  /// Keeps `loaded`, the comparison of `file` read since the change on disk of `generation`,
  /// unless the files changed on disk again meanwhile.
  func keep(_ loaded: LoadedFile, of file: CollectedFile, readIn generation: Int) {
    guard generation == diskGeneration else { return }
    loadedFiles[file] = loaded
  }

  /// Reads the file after `file` in the list ahead, and forgets the files that are not beside
  /// the one in view.
  private func readAhead(after file: CollectedFile) async {
    guard let collection else { return }
    let next = neighborIndex(forward: true)
    let neighbors = [neighborIndex(forward: false), fileIndex, next].compactMap(\.self)
    let kept = Set(neighbors.map { collection.files[$0] })
    loadedFiles = loadedFiles.filter { kept.contains($0.key) }
    if let next {
      _ = await loaded(collection.files[next])
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
  ) async throws(SessionLoadingError) -> LoadedFile {
    do {
      return LoadedFile(
        session: try await Session.loadDiff(
          old: file.old, new: file.new, mode: mode, ignoring: rules),
        unavailable: nil)
    } catch {
      let unavailable = UnavailableComparison(old: file.old, new: file.new, reason: error)
      return LoadedFile(session: try await unavailable.emptySession(), unavailable: unavailable)
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
