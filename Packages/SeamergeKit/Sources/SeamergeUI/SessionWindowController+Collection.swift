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
}

/// A file of a collection as the window read it: its comparison, or the empty one of a file it
/// cannot compare, with the reason.
struct LoadedFile {
  var session: Session
  var unavailable: UnavailableComparison?
}

extension SessionWindowController {
  /// Opens a window for `collection`: the list of its files in the sidebar, once there are two,
  /// and the first file beside it, drawn and started as `settings` say.
  ///
  /// The window keeps showing files as the collection receives them.
  ///
  /// - Precondition: The collection has a file.
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if not even the headers of the first file
  ///   can be made.
  public convenience init(
    collection: FileCollection, undoManager: UndoManager, settings: UserSettings
  ) async throws(SessionLoadingError) {
    guard let file = collection.files.first else {
      preconditionFailure("A window of a collection needs a file to show")
    }
    let loaded = try await Self.load(file, mode: settings.comparisonMode)
    self.init(
      session: loaded.session, context: Self.context(of: file, at: 0, in: collection),
      undoManager: undoManager, displayOptions: .current(in: .shared), pasteboard: .general,
      workspace: NSWorkspace.shared, prompts: SessionSheets(), doneStyle: .standard,
      settings: settings, syntaxChoices: .shared, window: SessionWindow(),
      unavailable: loaded.unavailable, collection: collection)
    observeDisplayOptions()
  }

  /// Shows the file after the one in view.
  @objc func showNextFile(_ sender: Any?) {
    guard canPerform(.nextFile) else { return }
    showFile(at: fileIndex + 1)
  }

  /// Shows the file before the one in view.
  @objc func showPreviousFile(_ sender: Any?) {
    guard canPerform(.previousFile) else { return }
    showFile(at: fileIndex - 1)
  }

  /// Shows the file at `index` of the collection, once it is read, where the window left it, or
  /// at its first change; the focus stays where it is.
  func showFile(at index: Int) {
    guard let collection, collection.files.indices.contains(index), index != fileIndex else {
      return
    }
    let shown = collection.files[fileIndex]
    filePlaces[shown.path] = currentPlace
    fileIndex = index
    collectionLayout?.fileList.select(index)
    let file = collection.files[index]
    fileLoad?.cancel()
    fileLoad = Task { [weak self] in
      guard let self, let loaded = await self.loaded(file), !Task.isCancelled,
        collection.files.indices.contains(fileIndex), collection.files[fileIndex] == file
      else { return }
      show(loaded, of: file)
      await readAhead(after: file)
    }
  }

  /// Sets up the list of the files and follows the collection as it receives more.
  func setUpCollection() {
    guard let collection, let collectionLayout else { return }
    // Files may have come while the window read the first one, some of them before it.
    fileIndex = collection.files.firstIndex { $0.path == context.difftool?.path } ?? 0
    collectionLayout.fileList.delegate = self
    collectionLayout.sidebarDidChange = { [weak self] in self?.updateMinimumSize() }
    collectionLayout.fileList.show(collection.files, selecting: fileIndex)
    collection.onChange = { [weak self] change in self?.collectionDidChange(change) }
    if collection.files.indices.contains(fileIndex) {
      loadedFiles[collection.files[fileIndex].path] = LoadedFile(
        session: presentation.changes.session, unavailable: unavailable)
    }
    showReceiving()
  }

  private func collectionDidChange(_ change: FileCollection.Change) {
    guard let collection, let fileList = collectionLayout?.fileList else { return }
    switch change {
    case .inserted(let index):
      if index <= fileIndex, collection.files.count > 1 {
        fileIndex += 1
      }
      fileList.insert(collection.files[index], at: index, selecting: fileIndex)
    case .complete:
      if collection.files.count > 1 {
        presentation.announce(FileListViewController.receivedText(collection.files.count))
      }
    }
    showReceiving()
    context.difftool?.filePosition = Self.position(of: fileIndex, in: collection)
    sessionDidChange()
    stateDidChange()
  }

  /// Shows below the list how many files have come while more come, and the list itself once
  /// there are two.
  private func showReceiving() {
    guard let collection, let collectionLayout else { return }
    let hasSeveralFiles = collection.files.count > 1
    collectionLayout.fileList.showReceiving(
      collection.files.count, of: collection.expectedCount, isReceiving: collection.isReceiving)
    collectionLayout.hasSeveralFiles = hasSeveralFiles
    toolbar.showsSidebarButton(hasSeveralFiles)
  }

  /// Shows `loaded`, the comparison of `file`, in place of the file in view.
  private func show(_ loaded: LoadedFile, of file: CollectedFile) {
    guard let collection else { return }
    context = Self.context(of: file, at: fileIndex, in: collection)
    let session = loaded.session
    unavailable = loaded.unavailable
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
      currentBlock: presentation.currentBlock, row: place.row, fraction: place.fraction)
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
    pane.scroll(toPlaceRowAtReadingLine: place.row, fraction: place.fraction, motion: .cut)
  }

  /// The comparison of `file` in the comparison mode of the window, from those read already or
  /// read now; `nil` if it cannot even be shown as a file that cannot be compared.
  private func loaded(_ file: CollectedFile) async -> LoadedFile? {
    let mode = comparisonOptions.mode
    if let loaded = loadedFiles[file.path], loaded.session.options.mode == mode {
      return loaded
    }
    do {
      let loaded = try await Self.load(file, mode: mode)
      loadedFiles[file.path] = loaded
      return loaded
    } catch {
      Self.logger.error("Cannot show \(file.path, privacy: .public): \(error, privacy: .public)")
      return nil
    }
  }

  /// Reads the file after `file` ahead, and forgets the files that are not beside the one in
  /// view.
  private func readAhead(after file: CollectedFile) async {
    guard let collection else { return }
    let neighbors = [fileIndex - 1, fileIndex, fileIndex + 1].filter(
      collection.files.indices.contains)
    let kept = Set(neighbors.map { collection.files[$0].path })
    loadedFiles = loadedFiles.filter { kept.contains($0.key) }
    if neighbors.last.map({ $0 > fileIndex }) == true, let next = neighbors.last {
      _ = await loaded(collection.files[next])
    }
  }

  /// Reads both sides of `file` and compares them in `mode`; a file that cannot be compared,
  /// such as an image, gets an empty comparison that names it, and the reason.
  ///
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if not even the empty comparison can be
  ///   made.
  static func load(
    _ file: CollectedFile, mode: ComparisonMode
  ) async throws(SessionLoadingError) -> LoadedFile {
    do {
      return LoadedFile(
        session: try await Session.loadDiff(old: file.old, new: file.new, mode: mode),
        unavailable: nil)
    } catch {
      let unavailable = UnavailableComparison(old: file.old, new: file.new, reason: error)
      return LoadedFile(session: try await unavailable.emptySession(), unavailable: unavailable)
    }
  }

  /// What the window knows about `file`, the file at `index` of `collection`.
  static func context(
    of file: CollectedFile, at index: Int, in collection: FileCollection
  ) -> SessionContext {
    var difftool = file.difftool
    difftool.filePosition = position(of: index, in: collection)
    return SessionContext(difftool: difftool)
  }

  /// The position of the file at `index` among the files of `collection`, counted from 1, among
  /// as many as Git announced or have come.
  private static func position(of index: Int, in collection: FileCollection) -> FilePosition {
    FilePosition(
      number: index + 1, count: max(collection.expectedCount ?? 0, collection.files.count))
  }
}

extension SessionWindowController: FileListDelegate {
  func fileList(_ fileList: FileListViewController, didSelectFileAt index: Int) {
    showFile(at: index)
  }
}
