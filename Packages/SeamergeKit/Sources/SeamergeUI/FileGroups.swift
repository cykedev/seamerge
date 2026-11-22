import Foundation

/// The files of a list grouped by the folder they are in, as the sidebar of a window that
/// compares several files shows them: the files at the top first, without a folder, then one
/// group for each folder, its files in the order given.
struct FileGroups: Equatable {
  /// How the groups of folders follow each other.
  enum FolderOrder {
    /// Each folder where its first file stands, as for files in the order of Git; a folder may
    /// then follow a folder in it.
    case firstFile

    /// By the path of the folder as the Finder sorts names, as for files sorted by path; each
    /// folder then comes before the folders in it.
    case path
  }

  /// A folder and the files in it.
  struct Group: Equatable {
    /// The folder of the files, relative to the top; empty for the files at the top.
    let folder: String

    /// The positions of the files in the order the groups were made from.
    var members: [Int]
  }

  /// The groups in the order the list shows them; the one of the files at the top, if there are
  /// any, comes first.
  private(set) var groups: [Group]

  /// How many files the groups hold.
  private(set) var fileCount: Int

  /// Groups the files at `paths`, relative to the top and in the order of the list, by their
  /// folder, the folders in `folderOrder`.
  init(paths: some Sequence<String>, folderOrder: FolderOrder) {
    var groups: [Group] = []
    var groupOfFolder: [Substring: Int] = [:]
    var count = 0
    for (position, path) in paths.enumerated() {
      let folder = Self.folder(of: path)
      if let group = groupOfFolder[folder] {
        groups[group].members.append(position)
      } else {
        groupOfFolder[folder] = groups.count
        groups.append(Group(folder: String(folder), members: [position]))
      }
      count += 1
    }
    switch folderOrder {
    case .firstFile:
      // The groups stand in the order of their first file already; the top comes first.
      if let top = groupOfFolder[""], top > 0 {
        groups.insert(groups.remove(at: top), at: 0)
      }
    case .path:
      groups.sort { first, second in
        guard first.folder.isEmpty == second.folder.isEmpty else { return first.folder.isEmpty }
        return first.folder.localizedStandardCompare(second.folder) == .orderedAscending
      }
    }
    self.groups = groups
    fileCount = count
  }

  private init(groups: [Group], fileCount: Int) {
    self.groups = groups
    self.fileCount = fileCount
  }

  /// The positions of the files in the order the groups show them.
  var order: [Int] {
    var order: [Int] = []
    order.reserveCapacity(fileCount)
    for group in groups {
      order += group.members
    }
    return order
  }

  /// The groups with only the files that `isIncluded`, and without the groups left empty.
  func filter(_ isIncluded: (Int) -> Bool) -> FileGroups {
    var count = 0
    var filtered: [Group] = []
    for group in groups {
      let members = group.members.filter(isIncluded)
      guard !members.isEmpty else { continue }
      filtered.append(Group(folder: group.folder, members: members))
      count += members.count
    }
    return FileGroups(groups: filtered, fileCount: count)
  }

  /// The folder of the file at `path`: all before its last slash, or nothing for a file at the
  /// top.
  static func folder(of path: String) -> Substring {
    guard let slash = path.utf8.lastIndex(of: UInt8(ascii: "/")) else { return "" }
    return path[..<slash]
  }
}
