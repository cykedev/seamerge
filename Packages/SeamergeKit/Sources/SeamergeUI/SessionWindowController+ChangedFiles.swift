import AppKit
import FolderCompare
import MergeModel
import os

/// The files of a comparison with copied changes: which they are, how the window marks them, and
/// saving them, each into its own file as it is on disk.
extension SessionWindowController {
  /// Decides once which files of the comparison shown may be written, as the window shows files
  /// it did not show before.
  func updateWritableSides() {
    let inputs = presentation.changes.session.inputs
    let urls = [inputs.a.url, inputs.b.url]
    guard urls != writableFileURLs || writableSides == nil else { return }
    writableFileURLs = urls
    writableSides = inputs.a.url.flatMap { old in
      inputs.b.url.map { new in
        WritableSides(
          old: SessionFile(url: old, label: inputs.a.label),
          new: SessionFile(url: new, label: inputs.b.label), context: context)
      }
    }
  }

  /// Notes what the file of `role` holds on disk before the first copy changes it, unless the
  /// window knows that already.
  func noteFileBeforeCopying(to role: Role) {
    guard let file = presentation.changes.session.inputs[role], let url = file.url,
      filesOnDisk[url] == nil
    else { return }
    filesOnDisk.note(file.bytes, at: url)
  }

  /// Finds the files of the comparison shown whose copied changes are not saved, says so in
  /// their headers, the close button and the list of the files, and tells VoiceOver nothing,
  /// since the copy itself was announced.
  ///
  /// Only the files of a comparison whose lines the window shows count; while it waits for the
  /// lines of a file of its collection, its panes stand empty below the headers.
  func updateEditedFiles() {
    let session = presentation.changes.session
    var edited: Set<Role> = []
    if case .ready = phase, !showsHeadersOnly, session.kind == .diff, binaryMerge == nil {
      updateWritableSides()
      if let writableSides {
        edited = Set(
          session.inputs.filter { role, file in
            writableSides.contains(role) && filesOnDisk.hasChanges(file)
          }.map(\.role))
      }
    }
    editedRoles = edited
    var headers = presentation.headers
    for role in Array(headers.keys) {
      headers[role]?.isEdited = edited.contains(role)
    }
    presentation.show(headers)
    markChangedFilesInTheList()
  }

  /// The comparison shown with its copied changes, if it has any.
  var shownChanges: ChangedComparison? {
    editedRoles.isEmpty
      ? nil : ChangedComparison(session: presentation.changes.session, roles: editedRoles)
  }

  /// Whether a file of the window has copied changes that are not saved: one of the comparison
  /// shown, or of another file of its collection.
  var hasChangedFiles: Bool {
    !editedRoles.isEmpty || !(collectionNavigator?.changedFiles.isEmpty ?? true)
  }

  /// The files with copied changes that are not saved: those of the comparison shown, then
  /// those that the navigator keeps for the files of the collection, in the order of the list,
  /// each with the path of its file in the collection; `keptAt` is `nil` for a file of the
  /// comparison shown.
  ///
  /// Either kind was decided writable as the window showed it. A file that the window is about
  /// to show again still counts as kept until its lines are there, while the panes stand empty.
  /// Each file comes once: as the window goes to another file, it keeps the changes of the file
  /// it still shows for a moment, which are the same.
  private var changedFiles: [(file: SourceFile, keptAt: String?)] {
    var files: [(SourceFile, String?)] = (shownChanges?.changedFiles ?? []).map { ($0, nil) }
    if let collectionNavigator {
      let kept = collectionNavigator.changedFiles
      var listedURLs = Set(files.compactMap(\.0.url))
      for file in collectionNavigator.collection.files {
        guard let changed = kept[file.path] else { continue }
        for changedFile in changed.changedFiles {
          if let url = changedFile.url, !listedURLs.insert(url).inserted {
            continue
          }
          files.append((changedFile, file.path))
        }
      }
    }
    return files
  }

  /// The names of the files with copied changes, as the sheets say them.
  var changedFileNames: [String] {
    changedFiles.map { Self.name(of: $0.file) }
  }

  /// The name of `file` in a sheet: that of its file on disk.
  private static func name(of file: SourceFile) -> String {
    file.url?.lastPathComponent ?? file.label
  }

  /// Shows a dot at each file of the list with copied changes that are not saved.
  ///
  /// The comparison shown counts for the file in view only while it is that file's: as the
  /// window goes to another file, it shows the one it leaves for a moment.
  func markChangedFilesInTheList() {
    guard let collectionNavigator, let fileList = collectionLayout?.fileList else { return }
    var paths = Set(collectionNavigator.changedFiles.keys)
    let inputs = presentation.changes.session.inputs
    if !editedRoles.isEmpty, let shown = collectionNavigator.shownFile,
      shown.old.url == inputs.a.url, shown.new.url == inputs.b.url
    {
      paths.insert(shown.path)
    }
    fileList.changedPaths = paths
  }

  /// Asks whether to save the files with copied changes, if there are any, and saves them if so;
  /// tells whether the window may go on, which it may not after Cancel or a failed save.
  func saveChangedFilesAskingFirst() async -> Bool {
    let names = changedFileNames
    guard !names.isEmpty else { return true }
    guard let window, !isAskingToClose else { return false }
    window.makeKeyAndOrderFront(nil)
    isAskingToClose = true
    let choice = await prompts.confirmSavingChanges(to: names, in: window)
    isAskingToClose = false
    switch choice {
    case .save: return await saveChangedFiles()
    case .discard: return true
    case .cancel: return false
    }
  }

  /// Writes every file with copied changes into its file on disk, and tells whether all of them
  /// were written.
  ///
  /// Each file keeps its encoding, byte order mark and line endings, which the copy gave it,
  /// and its permissions; a symbolic link stays, and the file it leads to is written. A file is
  /// replaced atomically: a failure leaves it as it was, keeps the window as it is and says why,
  /// and the files after it are not written. If another app changed a file since the window
  /// read it, a sheet asks whether to keep the window's version or to reload the file, after
  /// which nothing more is written. A file whose encoding could not hold the copied text holds
  /// it in UTF-8, which a sheet offers first. Only the files that the window decided writable
  /// are among them, never a copy of Git.
  @discardableResult
  func saveChangedFiles() async -> Bool {
    guard let window else { return false }
    isSaving = true
    defer {
      isSaving = false
      diskWatch.lookAgainIfAsked()
    }
    var savedNames: [String] = []
    defer { didSave(savedNames) }
    for (file, keptAt) in changedFiles {
      let name = Self.name(of: file)
      guard let url = file.url else {
        Self.logger.fault("A changed file has no location: \(name, privacy: .public)")
        return false
      }
      if let changed = FileManager.default.contents(atPath: url.path(percentEncoded: false)),
        changed != filesOnDisk[url]
      {
        filesOnDisk.note(changed, at: url)
        diskWatch.remember(changed, at: url)
        guard !(await prompts.confirmReloadingChangedFile(name, in: window)) else {
          await reload(file, from: changed, keptAt: keptAt)
          return false
        }
      }
      if file.encoding == .utf8, let known = filesOnDisk[url],
        let encoding = SourceFile(bytes: known, label: name).encoding, encoding != .utf8
      {
        guard await prompts.offerUTF8(saving: name, in: encoding, in: window) else { return false }
      }
      do {
        try FileReplacement.replace(url, with: file.bytes)
      } catch {
        Self.logger.error("Saving \(url.path, privacy: .public) failed: \(error, privacy: .public)")
        await prompts.reportFailedSaving(name, reason: error.localizedDescription, in: window)
        return false
      }
      filesOnDisk.note(file.bytes, at: url)
      diskWatch.remember(file.bytes, at: url)
      savedNames.append(name)
      if let path = keptAt ?? collectionNavigator?.shownFile?.path {
        collectionNavigator?.forgetReading(at: path)
      }
    }
    return true
  }

  /// Takes the saved files as they are on disk now: forgets the changes kept of the files that
  /// the window does not show, marks the files anew, and tells VoiceOver which it saved.
  private func didSave(_ names: [String]) {
    guard !names.isEmpty else { return }
    if let collectionNavigator {
      for (path, changed) in collectionNavigator.changedFiles
      where !changed.changedFiles.contains(where: filesOnDisk.hasChanges) {
        collectionNavigator.forgetChanges(at: path)
      }
    }
    updateEditedFiles()
    stateDidChange()
    presentation.announce(
      names.count == 1
        ? String(
          localized: "Saved \(names[0])", bundle: .module,
          comment: "VoiceOver after saving, such as Saved story.txt.")
        : String(
          localized: "Saved \(names.count) files", bundle: .module,
          comment: "VoiceOver after saving the files of a comparison, such as Saved 2 files."))
  }

  /// Takes `bytes`, which another app wrote into the file of `file` while it had copied changes,
  /// in place of those changes: of the comparison shown, as a step of undo, or of a file that
  /// the navigator keeps at `keptAt`, which the window reads anew when it shows it again.
  private func reload(_ file: SourceFile, from bytes: Data, keptAt path: String?) async {
    guard let path else {
      let session = presentation.changes.session
      guard let role = session.inputs.first(where: { $0.value.url == file.url })?.role else {
        return
      }
      await reloadFiles([role: SourceFile(bytes: bytes, label: file.label, url: file.url)])
      return
    }
    collectionNavigator?.forgetChanges(at: path)
    if path == collectionNavigator?.shownFile?.path {
      // The window waits to show the copies it kept; once it shows them, it takes the file as
      // it is on disk instead, as for any change of a file without copies.
      diskWatch.filesMayHaveChanged()
    }
    markChangedFilesInTheList()
    stateDidChange()
  }
}
