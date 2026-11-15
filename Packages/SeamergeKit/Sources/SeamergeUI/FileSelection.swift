import Foundation
import MergeModel

/// A field of the window Compare Files, in the order of the panes.
enum FileSlot: CaseIterable, Sendable {
  /// The older file of a comparison, or A of a merge.
  case left

  /// The common ancestor, which makes a merge of the files.
  case base

  /// The newer file of a comparison, or B of a merge.
  case right

  /// The word below the field: Left, Base (Optional) and Right until the base is chosen, then
  /// A, Base and B, which only mean something in a merge; Left Folder and Right Folder for an
  /// outer field that `isFolder`.
  func title(hasBase: Bool, isFolder: Bool = false) -> String {
    switch (self, isFolder) {
    case (.left, true):
      return String(
        localized: "Left Folder", bundle: .module,
        comment: "Compare Files: the role of the left field once a folder is chosen.")
    case (.right, true):
      return String(
        localized: "Right Folder", bundle: .module,
        comment: "Compare Files: the role of the right field once a folder is chosen.")
    default:
      return fileTitle(hasBase: hasBase)
    }
  }

  private func fileTitle(hasBase: Bool) -> String {
    switch (self, hasBase) {
    case (.left, false):
      String(localized: "Left", bundle: .module, comment: "Compare Files: the role of a field.")
    case (.right, false):
      String(localized: "Right", bundle: .module, comment: "Compare Files: the role of a field.")
    case (.base, false):
      String(
        localized: "Base (Optional)", bundle: .module,
        comment: "Compare Files: the role of the middle field, which may stay empty.")
    case (.left, true): Role.a.letter
    case (.base, true): Role.base.letter
    case (.right, true): Role.b.letter
    }
  }

  /// The role as VoiceOver says it, such as “Base, optional”.
  func accessibilityTitle(hasBase: Bool, isFolder: Bool = false) -> String {
    guard self == .base, !hasBase else { return title(hasBase: hasBase, isFolder: isFolder) }
    return String(
      localized: "Base, optional", bundle: .module,
      comment: "VoiceOver: the role of the empty middle field of Compare Files.")
  }
}

extension FileSlot {
  /// Why the base takes no file while the outer fields hold folders.
  static var foldersWithoutBase: String {
    String(
      localized: "Folders are compared without a base.", bundle: .module,
      comment:
        "Compare Files: help tag of the base field, and the note below the fields, while folders are chosen."
    )
  }
}

/// The files and folders in the fields of the window Compare Files, and the rules by which dropped
/// files take their places.
///
/// A folder goes only into an outer field: two folders are compared file by file, without a
/// base. A URL names a folder where it is a directory path, as ``FileDrop`` and the open panel
/// give it.
struct FileSelection: Equatable {
  private var files: [FileSlot: URL] = [:]

  /// The file in `slot`, if there is one.
  subscript(slot: FileSlot) -> URL? {
    get { files[slot] }
    set { files[slot] = newValue }
  }

  /// Whether the base is chosen, which makes a merge of the files.
  var hasBase: Bool { files[.base] != nil }

  /// Whether no field has a file.
  var isEmpty: Bool { files.isEmpty }

  /// Whether an outer field holds a folder.
  var hasFolder: Bool {
    [files[.left], files[.right]].contains { $0?.hasDirectoryPath == true }
  }

  /// Whether the field `slot` is named for a folder: it holds one, or it is an empty outer field
  /// while the other holds one, which tells what it takes.
  func namesFolder(_ slot: FileSlot) -> Bool {
    guard slot != .base else { return false }
    return files[slot].map(\.hasDirectoryPath) ?? hasFolder
  }

  /// The word below the field `slot`, as the files in the fields name it.
  func title(of slot: FileSlot) -> String {
    slot.title(hasBase: hasBase, isFolder: namesFolder(slot))
  }

  /// The files in the fields, as the window opens them: two outer ones to compare, all three to
  /// merge, or two different folders without a base; `nil` otherwise.
  var comparison: FileComparison? {
    guard let left = files[.left], let right = files[.right], problem == nil else { return nil }
    if hasFolder {
      return FileComparison(folders: FolderPair(left: left, right: right))
    }
    return FileComparison(left: left, base: files[.base], right: right)
  }

  /// Why the fields cannot be opened although they hold what would be enough, if they do not go
  /// together.
  var problem: Problem? {
    guard hasFolder else { return nil }
    if files[.base] != nil {
      return .baseWithFolders
    }
    guard let left = files[.left], let right = files[.right] else { return nil }
    guard left.hasDirectoryPath, right.hasDirectoryPath else { return .fileAndFolder }
    return left.standardizedFileURL.path == right.standardizedFileURL.path ? .sameFolder : nil
  }

  /// Fields that do not go together.
  enum Problem: Equatable {
    /// An outer field holds a folder and the other a file.
    case fileAndFolder

    /// Both outer fields hold the same folder.
    case sameFolder

    /// An outer field holds a folder while the base holds a file.
    case baseWithFolders

    /// What the window says about it below the fields.
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
      case .baseWithFolders:
        FileSlot.foldersWithoutBase
      }
    }
  }

  /// Where `urls` go when they are dropped on the field `slot`, or anywhere on the window when
  /// `slot` is `nil`; `nil` if the window takes none of them.
  ///
  /// Three files fill all fields from left to right, two files or folders the outer ones. One
  /// file takes the field it is dropped on, or else the first free one of Left, Right and Base;
  /// one folder the same, except Base. Folders go nowhere unless `acceptsFolders`.
  func places(
    for urls: [URL], droppedOn slot: FileSlot?, acceptsFolders: Bool
  ) -> [FileSlot: URL]? {
    let hasFolders = urls.contains(where: \.hasDirectoryPath)
    guard !hasFolders || (acceptsFolders && slot != .base && urls.count <= 2) else { return nil }
    switch urls.count {
    case 3:
      return [.left: urls[0], .base: urls[1], .right: urls[2]]
    case 2:
      return [.left: urls[0], .right: urls[1]]
    case 1:
      let candidates: [FileSlot] = hasFolders ? [.left, .right] : [.left, .right, .base]
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
