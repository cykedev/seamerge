import FolderCompare
import Foundation
import MergeModel

/// A field of the sheets Compare Files and Merge Files, in the order of the panes.
enum FileSlot: CaseIterable, Sendable {
  /// The older file of a comparison, or A of a merge.
  case left

  /// The common ancestor of a merge.
  case base

  /// The newer file of a comparison, or B of a merge.
  case right

  /// The fields of a sheet for a session of `kind`: Left and Right to compare, all three to
  /// merge.
  static func slots(for kind: Session.Kind) -> [FileSlot] {
    kind == .merge ? allCases : [.left, .right]
  }

  /// The word below the field in a sheet for a session of `kind`: Left and Right to compare, or
  /// Left Folder and Right Folder for a field that `isFolder`; A, Base and B to merge.
  func title(for kind: Session.Kind, isFolder: Bool = false) -> String {
    switch (self, kind, isFolder) {
    case (.left, .diff, true):
      String(
        localized: "Left Folder", bundle: .module,
        comment: "Compare Files: the role of the left field once a folder is chosen.")
    case (.right, .diff, true):
      String(
        localized: "Right Folder", bundle: .module,
        comment: "Compare Files: the role of the right field once a folder is chosen.")
    case (.left, .diff, false):
      String(localized: "Left", bundle: .module, comment: "Compare Files: the role of a field.")
    case (.right, .diff, false):
      String(localized: "Right", bundle: .module, comment: "Compare Files: the role of a field.")
    case (.left, _, _): Role.a.letter
    case (.base, _, _): Role.base.letter
    case (.right, _, _): Role.b.letter
    }
  }
}

/// The files and folders in the fields of a sheet Compare Files or Merge Files, and the rules by
/// which dropped files take their places.
///
/// To compare, there are two fields, which take two files or two folders; folders are compared
/// file by file. To merge, there are three fields, which take files only. A URL names a folder
/// where it is a directory path, as ``FileDrop`` and the open panel give it.
struct FileSelection: Equatable {
  /// Whether the fields are those of a comparison or of a merge.
  let kind: Session.Kind

  private var files: [FileSlot: URL] = [:]

  /// Creates the empty fields of a sheet for a session of `kind`.
  init(kind: Session.Kind) {
    self.kind = kind
  }

  /// The fields, from left to right.
  var slots: [FileSlot] { FileSlot.slots(for: kind) }

  /// The file in `slot`, if there is one.
  subscript(slot: FileSlot) -> URL? {
    get { files[slot] }
    set { files[slot] = newValue }
  }

  /// Whether no field has a file.
  var isEmpty: Bool { files.isEmpty }

  /// Whether an outer field holds a folder.
  var hasFolder: Bool {
    [files[.left], files[.right]].contains { $0?.hasDirectoryPath == true }
  }

  /// Whether the field `slot` is named for a folder: it holds one, or it is an empty field of a
  /// comparison while the other holds one, which tells what it takes.
  func namesFolder(_ slot: FileSlot) -> Bool {
    guard kind == .diff else { return false }
    return files[slot].map(\.hasDirectoryPath) ?? hasFolder
  }

  /// The word below the field `slot`, as the files in the fields name it.
  func title(of slot: FileSlot) -> String {
    slot.title(for: kind, isFolder: namesFolder(slot))
  }

  /// The files in the fields, as the sheet opens them: two files or two different folders to
  /// compare, three files to merge; `nil` while a field is empty or the fields do not go
  /// together.
  var comparison: FileComparison? {
    guard let left = files[.left], let right = files[.right], problem == nil else { return nil }
    switch kind {
    case .diff:
      return hasFolder
        ? FileComparison(folders: FolderPair(left: left, right: right))
        : FileComparison(left: left, right: right)
    case .merge:
      return files[.base].map { FileComparison(left: left, base: $0, right: right) }
    }
  }

  /// Why the fields cannot be opened although they hold what would be enough, if they do not go
  /// together.
  var problem: Problem? {
    guard hasFolder, let left = files[.left], let right = files[.right] else { return nil }
    guard left.hasDirectoryPath, right.hasDirectoryPath else { return .fileAndFolder }
    return left.standardizedFileURL.path == right.standardizedFileURL.path ? .sameFolder : nil
  }

  /// Fields that do not go together.
  enum Problem: Equatable {
    /// One field holds a folder and the other a file.
    case fileAndFolder

    /// Both fields hold the same folder.
    case sameFolder

    /// What the sheet says about it below the fields.
    var message: String {
      switch self {
      case .fileAndFolder:
        String(
          localized: "Choose two files or two folders.", bundle: .module,
          comment: "Compare Files: a file and a folder are chosen, which cannot be compared.")
      case .sameFolder:
        String(
          localized: "Choose two different folders.", bundle: .module,
          comment: "Compare Files: the same folder is chosen twice.")
      }
    }
  }

  /// Where `urls` go when they are dropped on the field `slot`, or anywhere on the sheet when
  /// `slot` is `nil`; `nil` if the sheet takes none of them.
  ///
  /// As many files as there are fields fill them from left to right, and two files fill the
  /// outer fields of a merge. One file takes the field it is dropped on, or else the first free
  /// one of Left, Right and Base. Folders go only into a comparison that `acceptsFolders`, two
  /// at most.
  func places(
    for urls: [URL], droppedOn slot: FileSlot?, acceptsFolders: Bool
  ) -> [FileSlot: URL]? {
    let hasFolders = urls.contains(where: \.hasDirectoryPath)
    guard !hasFolders || (acceptsFolders && kind == .diff) else { return nil }
    if let slot, !slots.contains(slot) {
      return nil
    }
    switch urls.count {
    case slots.count:
      return Dictionary(uniqueKeysWithValues: zip(slots, urls))
    case 2:
      return [.left: urls[0], .right: urls[1]]
    case 1:
      let candidates = [FileSlot.left, .right, .base].filter(slots.contains)
      guard let target = slot ?? candidates.first(where: { files[$0] == nil }) else {
        return nil
      }
      return [target: urls[0]]
    default:
      return nil
    }
  }

  /// Puts the files of `places` in their fields.
  mutating func fill(_ places: [FileSlot: URL]) {
    files.merge(places) { $1 }
  }

  /// Swaps the files of two fields, whether or not both have one.
  mutating func swap(_ first: FileSlot, _ second: FileSlot) {
    (files[first], files[second]) = (files[second], files[first])
  }
}
