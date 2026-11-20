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

/// Which file of a collection a window shows, which files its list shows, and what the window
/// has read of them.
///
/// The navigator never shows a file; the window does, and asks it which. It keeps the place the
/// window showed in each file, for when the user comes back to it, and the files the window has
/// read: the one in view and those beside it, which it reads ahead, so that Next File and
/// Previous File show at once. A reading that began before the files changed on disk is not
/// kept.
@MainActor
final class CollectionNavigator {
  /// What became of the file in view after the files of the collection changed.
  enum Following: Equatable {
    /// It is there as before, or there is none.
    case stays

    /// It is there with other sides, or became readable or unreadable, and is read anew.
    case readsAnew(CollectedFile)

    /// It went from the collection; the window shows none for now. `next` is the index of the
    /// first file that follows it in the order, if there is one.
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

  /// The indices of the files of the collection that the list shows, in order.
  private(set) var listedIndices: [Int] = []

  /// The place in each file that the window showed, by path.
  private var places: [String: FilePlace] = [:]

  /// The files that the window has read: the one it shows and those beside it.
  ///
  /// A file whose sides or change differ since is another file, which is read anew.
  private(set) var readFiles: [CollectedFile: CollectedComparison] = [:]

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
    listFiles()
  }

  /// Lists the files of the collection that the filter lets through.
  func listFiles() {
    let (files, filter) = (collection.files, filter)
    listedIndices = files.indices.filter { filter.includes(files[$0]) }
  }

  /// The files that the list shows, in order.
  var listedFiles: [CollectedFile] {
    listedIndices.map { collection.files[$0] }
  }

  /// The row of the list that shows the file at `index` of the collection, if the list shows it.
  func listedRow(of index: Int) -> Int? {
    let row = listedIndices.partitioningIndex { $0 >= index }
    return listedIndices.indices.contains(row) && listedIndices[row] == index ? row : nil
  }

  /// The row of the list that shows the file in view, if there is one and the list shows it.
  var shownRow: Int? {
    shownFile.flatMap { _ in listedRow(of: fileIndex) }
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

  /// The index of the file the list shows at or after `next` in the order of the collection, or
  /// of its last file if there is none; `nil` while the list is empty.
  func listedIndex(from next: Int?) -> Int? {
    next.flatMap { next in listedIndices.first { $0 >= next } } ?? listedIndices.last
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
      let next = collection.files.firstIndex { !$0.precedes(shown) }
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

  /// The comparison of `file` in `mode` without the text that `rules` match, from the files read
  /// already or read now; `nil` if it cannot even be shown as a file that cannot be compared.
  func comparison(
    of file: CollectedFile, mode: ComparisonMode, ignoring rules: [IgnoreRule]
  ) async -> CollectedComparison? {
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
