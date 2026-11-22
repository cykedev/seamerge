import FolderCompare
import Foundation
import GitSupport
import MergeModel
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

  /// When the window began to read the files, or `nil` if it did not read them.
  var readSince: Date?

  /// Reads both sides of `file` and compares them in `mode` without the text that the enabled
  /// rules of `rules` match; a file that cannot be compared, such as an image, gets an empty
  /// comparison that names it, and the reason.
  ///
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if not even the empty comparison can be
  ///   made.
  init(
    reading file: CollectedFile, mode: ComparisonMode, ignoring rules: [IgnoreRule]
  ) async throws(SessionLoadingError) {
    readSince = Date()
    do {
      session = try await Session.loadDiff(
        old: file.old, new: file.new, mode: mode, ignoring: rules)
      unavailable = nil
    } catch {
      let unavailable = UnavailableComparison(old: file.old, new: file.new, reason: error)
      session = try await unavailable.emptySession()
      self.unavailable = unavailable
    }
  }

  init(session: Session, unavailable: UnavailableComparison?) {
    self.session = session
    self.unavailable = unavailable
    readSince = nil
  }
}

/// A file of a collection whose copied changes are not saved, as the window showed it last.
struct ChangedComparison {
  /// The comparison of the file, whose changed sides hold the copied text.
  var session: Session

  /// The sides of the file with copied changes.
  var roles: Set<Role>

  /// The files of the changed sides, as the window holds them.
  var changedFiles: [SourceFile] {
    session.inputs.filter { roles.contains($0.role) }.map(\.value)
  }
}

/// Which file of a collection a window shows, which files its list shows, and what the window
/// has read of them.
///
/// The navigator never shows a file; the window does, and asks it which. It keeps the place the
/// window showed in each file, for when the user comes back to it, and the files the window has
/// read: the one in view and those beside it, which it reads ahead, so that Next File and
/// Previous File show at once. A reading that began before the files changed on disk is not
/// kept.
///
/// It also keeps the files with copied changes that the window does not show, so that their
/// changes survive going to another file; going back shows them as the window left them.
@MainActor
final class CollectionNavigator {
  /// What became of the file in view after the files of the collection changed.
  enum Following: Equatable {
    /// It is there as before, or there is none.
    case stays

    /// It is there with other sides, or became readable or unreadable, and is read anew.
    case readsAnew(CollectedFile)

    /// It went from the collection; the window shows none for now. `next` is the index of the
    /// file that follows where it stood in the order of the groups, if there is one.
    case went(next: Int?)
  }

  /// The files of the window.
  let collection: FileCollection

  /// Which files of the collection the list shows.
  private(set) var filter: FileFilter

  /// The index of the file the window shows among the files of the collection.
  private(set) var fileIndex = 0

  /// The file of the collection the window shows, or `nil` while it shows none, as before the
  /// first file of two folders is known.
  private(set) var shownFile: CollectedFile?

  /// The files of the collection that the list shows, grouped by folder, by their index in the
  /// collection.
  private(set) var listedGroups = FileGroups(paths: [], folderOrder: .firstFile)

  /// The indices of the files of the collection that the list shows, in the order it shows them.
  private(set) var listedIndices: [Int] = []

  /// Every file of the collection grouped by folder, whether the list shows it or not.
  private var groups = FileGroups(paths: [], folderOrder: .firstFile)

  /// Where each file of the collection stands among all of them in the order of the groups, by
  /// its index in the collection.
  private var ranks: [Int] = []

  /// The files of the collection as they were grouped last.
  private var groupedFiles: [CollectedFile]?

  /// The place in each file that the window showed, by path.
  private var places: [String: FilePlace] = [:]

  /// The files that the window has read: the one it shows and those beside it.
  ///
  /// A file whose sides or change differ since is another file, which is read anew.
  private(set) var readFiles: [CollectedFile: CollectedComparison] = [:]

  /// The files with copied changes that are not saved, by path, but the one in view, whose
  /// changes the window holds itself.
  private(set) var changedFiles: [String: ChangedComparison] = [:]

  /// How often the files of the folders changed on disk since the window opened; a reading that
  /// started before the last change is out of date when it ends.
  private(set) var diskGeneration = 0

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// Creates the navigator of `collection`, whose list shows the files that hold the same bytes
  /// on both sides as well if `showsIdenticalFiles`.
  init(collection: FileCollection, showsIdenticalFiles: Bool) {
    self.collection = collection
    filter = FileFilter(showsIdenticalFiles: showsIdenticalFiles)
  }

  /// Changes which files the list shows with `change`, and lists them anew.
  func changeFilter(_ change: (inout FileFilter) -> Void) {
    change(&filter)
    applyFilter()
  }

  /// Groups the files of the collection anew if they changed since they were grouped last, and
  /// lists those that the filter lets through.
  func listFiles() {
    // Arrays that share their storage compare at once; the files grouped last usually do.
    if collection.files != groupedFiles {
      group()
    }
    applyFilter()
  }

  /// The files that the list shows, in order.
  var listedFiles: [CollectedFile] {
    listedIndices.map { collection.files[$0] }
  }

  /// The row of the list that shows the file at `index` of the collection, counting files only,
  /// if the list shows it.
  func listedRow(of index: Int) -> Int? {
    guard let rank = rank(of: index) else { return nil }
    let row = listedIndices.partitioningIndex { ranks[$0] >= rank }
    return listedIndices.indices.contains(row) && listedIndices[row] == index ? row : nil
  }

  /// The row of the list that shows the file in view, if there is one and the list shows it.
  var shownRow: Int? {
    shownFile.flatMap { _ in listedRow(of: fileIndex) }
  }

  /// The index in the collection of the file that Next File, or Previous File if not `forward`,
  /// shows: the next one the list shows after the file in view, wherever that file stands in
  /// the order of the groups, even if the list leaves it out.
  func neighborIndex(forward: Bool) -> Int? {
    guard shownFile != nil, let rank = rank(of: fileIndex) else { return nil }
    let row = listedIndices.partitioningIndex { ranks[$0] >= rank }
    if forward {
      let next =
        listedIndices.indices.contains(row) && listedIndices[row] == fileIndex ? row + 1 : row
      return listedIndices.indices.contains(next) ? listedIndices[next] : nil
    }
    return row > 0 ? listedIndices[row - 1] : nil
  }

  /// The index of the file the list shows at or after the file at `next` in the order of the
  /// groups, or of its last file if there is none; `nil` while the list is empty.
  func listedIndex(from next: Int?) -> Int? {
    guard let rank = next.flatMap(rank(of:)) else { return listedIndices.last }
    return listedIndices.first { ranks[$0] >= rank } ?? listedIndices.last
  }

  /// How the folders of the collection follow each other: in the order of Git where Git
  /// numbered the files, else by path, as the files are sorted then.
  private var folderOrder: FileGroups.FolderOrder {
    collection.files.contains { $0.difftool.filePosition != nil } ? .firstFile : .path
  }

  /// Groups every file of the collection by folder and notes where each stands in their order.
  private func group() {
    let files = collection.files
    groupedFiles = files
    groups = FileGroups(paths: files.lazy.map(\.path), folderOrder: folderOrder)
    ranks = Array(repeating: 0, count: files.count)
    for (rank, index) in groups.order.enumerated() {
      ranks[index] = rank
    }
  }

  /// Lists the files that the filter lets through, in the order of the groups.
  private func applyFilter() {
    let (files, filter) = (collection.files, filter)
    listedGroups = groups.filter { filter.includes(files[$0]) }
    listedIndices = listedGroups.order
  }

  /// Where the file at `index` of the collection stands in the order of the groups, if it is
  /// among the files grouped last.
  private func rank(of index: Int) -> Int? {
    ranks.indices.contains(index) ? ranks[index] : nil
  }

  /// Where the file in view stands in the list: among as many files as Git announced or the list
  /// holds, while nothing is typed in the filter field; `nil` if the list leaves the file out.
  var filePosition: FilePosition? {
    guard let row = shownRow else { return nil }
    let count =
      filter.text.isEmpty
      ? max(collection.expectedCount ?? 0, listedIndices.count) : listedIndices.count
    return FilePosition(number: row + 1, count: count)
  }

  /// Whether `file` is the file in view, found by its path.
  ///
  /// What the list says about the file may have changed since, as when its sides became equal on
  /// disk. The window cancels a reading once the sides of the file in view change, so that the
  /// path is enough to tell the file; bytes that changed while it read them, it reloads once it
  /// shows them, as the watch of the files sees their date.
  func shows(_ file: CollectedFile) -> Bool {
    shownFile?.path == file.path
  }

  /// Whether the window can go to the file at `index`: one of the collection that it does not
  /// show yet.
  func canGo(toFileAt index: Int) -> Bool {
    collection.files.indices.contains(index) && (index != fileIndex || shownFile == nil)
  }

  /// Makes the file at `index` of the collection the file in view, and returns it.
  ///
  /// - Precondition: The collection has a file at `index`.
  func go(toFileAt index: Int) -> CollectedFile {
    precondition(collection.files.indices.contains(index), "The file is one of the collection")
    fileIndex = index
    shownFile = collection.files[index]
    return collection.files[index]
  }

  /// Keeps the file in view at its index after a file came at `index`.
  func fileWasInserted(at index: Int) {
    if shownFile != nil, index <= fileIndex, collection.files.count > 1 {
      fileIndex += 1
    }
  }

  /// Forgets the files read so far but the one in view, after the files of the folders changed
  /// on disk; those read ahead may be out of date even where their entry in the list reads the
  /// same.
  func filesChangedOnDisk() {
    readFiles = readFiles.filter { $0.key == shownFile }
    diskGeneration += 1
  }

  /// Forgets what the window read of the file in view, whose sides changed on disk since.
  ///
  /// Going back to the file reads it anew. A read still under way began before the change, so
  /// it is not kept either.
  func shownFileChangedOnDisk() {
    guard let shownFile else { return }
    readFiles = readFiles.filter { $0.key.path != shownFile.path }
    diskGeneration += 1
  }

  /// Finds the file in view again by its path after the files of the collection changed.
  ///
  /// A change of the bytes of the file in view, the window reloads by itself as it watches the
  /// file.
  func followShownFile() -> Following {
    guard let shown = shownFile else { return .stays }
    guard let index = collection.files.firstIndex(where: { $0.path == shown.path }) else {
      group()
      let next = successor(of: shown)
      shownFile = nil
      fileIndex = 0
      return .went(next: next)
    }
    fileIndex = index
    let file = collection.files[index]
    shownFile = file
    let isUnreadable = { (file: CollectedFile) in
      if case .unreadable = file.change { true } else { false }
    }
    guard
      file.old.url != shown.old.url || file.new.url != shown.new.url
        || isUnreadable(file) != isUnreadable(shown)
    else { return .stays }
    return .readsAnew(file)
  }

  /// The index of the file of the collection that `gone`, which went from it, would be followed
  /// by in the order of the groups, if any.
  private func successor(of gone: CollectedFile) -> Int? {
    let files = collection.files
    let position = files.firstIndex { !$0.precedes(gone) } ?? files.endIndex
    var paths = files.map(\.path)
    paths.insert(gone.path, at: position)
    let order = FileGroups(paths: paths, folderOrder: folderOrder).order
    guard let place = order.firstIndex(of: position), place + 1 < order.count else { return nil }
    let next = order[place + 1]
    return next > position ? next - 1 : next
  }

  /// Keeps `place` as the place in the file in view, which the window shows again when the user
  /// comes back to the file.
  func keepPlace(_ place: FilePlace) {
    guard let shownFile else { return }
    places[shownFile.path] = place
  }

  /// The place the window showed last in `file`, if it showed the file before.
  func place(of file: CollectedFile) -> FilePlace? {
    places[file.path]
  }

  /// Keeps `changed`, the comparison of the file in view with its copied changes, as the window
  /// goes to another file; `nil` keeps nothing, for a file without such changes.
  func keepChanges(_ changed: ChangedComparison?) {
    guard let shownFile else { return }
    changedFiles[shownFile.path] = changed
  }

  /// Hands the window the changes of the file in view, which it holds itself from now on.
  func takeChangesOfShownFile() {
    guard let shownFile else { return }
    changedFiles[shownFile.path] = nil
  }

  /// Forgets the changes of the file at `path` and what the window read of it, as after they
  /// were saved or the file was reloaded; going back to it reads it anew.
  func forgetChanges(at path: String) {
    changedFiles[path] = nil
    readFiles = readFiles.filter { $0.key.path != path }
  }

  /// Forgets the changes kept of the files that went from the collection or whose sides are
  /// other files now, as after the files of the folders changed on disk, and tells whether it
  /// forgot any.
  ///
  /// Their copies were made into files that nothing compares any more; writing them would put
  /// text where no one looks for it, so they go, as the file went.
  func forgetChangesOfFilesNoLongerCompared() -> Bool {
    let files = Dictionary(collection.files.map { ($0.path, $0) }) { first, _ in first }
    let gone = changedFiles.filter { path, changed in
      guard let file = files[path] else { return true }
      let inputs = changed.session.inputs
      return inputs.a.url != file.old.url || inputs.b.url != file.new.url
    }
    for path in gone.keys {
      Self.logger.notice("Forgetting the copied changes of \(path, privacy: .public), which went")
      changedFiles[path] = nil
    }
    return !gone.isEmpty
  }

  /// Forgets what the window read of the file at `path`, which holds other bytes on disk since,
  /// as after the window saved it.
  func forgetReading(at path: String) {
    readFiles = readFiles.filter { $0.key.path != path }
  }

  /// The comparison of `file` in `mode` without the text that `rules` match: the one with copied
  /// changes if the file has them, compared anew in `mode` with `rules` if the window compared it
  /// otherwise, else from the files read already or read now; `nil` if it cannot even be shown
  /// as a file that cannot be compared.
  func comparison(
    of file: CollectedFile, mode: ComparisonMode, ignoring rules: [IgnoreRule]
  ) async -> CollectedComparison? {
    if let changed = changedFiles[file.path] {
      return await comparison(of: changed, at: file.path, mode: mode, ignoring: rules)
    }
    if let collected = readFiles[file], collected.session.options.mode == mode,
      collected.unavailable != nil
        || collected.session.ignoreRules.hasTheSameEffect(as: rules)
    {
      return collected
    }
    let generation = diskGeneration
    do {
      let collected = try await CollectedComparison(reading: file, mode: mode, ignoring: rules)
      keep(collected, of: file, readIn: generation)
      return collected
    } catch {
      Self.logger.error("Cannot show \(file.path, privacy: .public): \(error, privacy: .public)")
      return nil
    }
  }

  /// The comparison of `changed`, the file at `path` with copied changes, in `mode` without the
  /// text that `rules` match; `nil` if its files cannot be compared so.
  private func comparison(
    of changed: ChangedComparison, at path: String, mode: ComparisonMode,
    ignoring rules: [IgnoreRule]
  ) async -> CollectedComparison? {
    let session = changed.session
    guard session.options.mode != mode || !session.ignoreRules.hasTheSameEffect(as: rules) else {
      return CollectedComparison(session: session, unavailable: nil)
    }
    do {
      let compared = try await Session.diff(
        old: session.inputs.a, new: session.inputs.b, mode: mode, ignoring: rules)
      // The window may have saved or reloaded the file meanwhile.
      if changedFiles[path] != nil {
        changedFiles[path] = ChangedComparison(session: compared, roles: changed.roles)
      }
      return CollectedComparison(session: compared, unavailable: nil)
    } catch {
      Self.logger.error("Cannot compare \(path, privacy: .public) anew: \(error, privacy: .public)")
      return nil
    }
  }

  /// Keeps `collected`, the comparison of `file` read since the change on disk of `generation`,
  /// unless the files changed on disk again meanwhile.
  func keep(_ collected: CollectedComparison, of file: CollectedFile, readIn generation: Int) {
    guard generation == diskGeneration else { return }
    readFiles[file] = collected
  }

  /// Reads the file after `file` in the list ahead in `mode` without the text that `rules`
  /// match, and forgets the files that are not beside the one in view; nothing once the window
  /// shows `file` no more, as after it went from the folders.
  func readAhead(
    after file: CollectedFile, mode: ComparisonMode, ignoring rules: [IgnoreRule]
  ) async {
    guard shows(file) else { return }
    let next = neighborIndex(forward: true)
    let neighbors = [neighborIndex(forward: false), fileIndex, next].compactMap(\.self)
    let kept = Set(neighbors.map { collection.files[$0] })
    readFiles = readFiles.filter { kept.contains($0.key) }
    if let next {
      _ = await comparison(of: collection.files[next], mode: mode, ignoring: rules)
    }
  }
}
