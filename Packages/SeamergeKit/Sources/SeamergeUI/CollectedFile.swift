import Foundation
public import GitSupport
public import MergeModel

/// One file of a window that compares several: its two sides and what Git says about them.
public struct CollectedFile: Sendable, Hashable {
  /// What happened to a file between its two sides.
  public enum Change: Sendable, Hashable {
    /// Both sides exist and differ.
    case modified

    /// The file is new: there is no earlier side.
    case added

    /// The file was deleted: there is no later side.
    case deleted

    /// Both sides exist and hold the same bytes; only a comparison of folders lists such files.
    case identical

    /// A side cannot be read, for the reason given, so that it is not known whether the sides
    /// differ.
    case unreadable(reason: String)
  }

  /// The older side, shown on the left; `/dev/null` for a new file.
  public var old: SessionFile {
    get { oldSide.file(label: path) }
    set { oldSide = .file(newValue) }
  }

  /// The newer side, shown on the right; `/dev/null` for a deleted file.
  public var new: SessionFile {
    get { newSide.file(label: path) }
    set { newSide = .file(newValue) }
  }

  /// The path of the file in the repository, what each side is and, from Git, the number of the
  /// file in its run.
  public var difftool: DifftoolContext

  /// What happened to the file.
  public let change: Change

  private var oldSide: Side
  private var newSide: Side

  /// Creates the description of a file of a collection, which is new or deleted where a side is
  /// missing and modified otherwise.
  public init(old: SessionFile, new: SessionFile, difftool: DifftoolContext) {
    self.init(
      old: old, new: new, difftool: difftool,
      change: FileOrigin(url: old.url) == .missing
        ? .added : FileOrigin(url: new.url) == .missing ? .deleted : .modified)
  }

  /// Creates the description of a file whose `change` is known, as a comparison of folders
  /// knows it.
  init(old: SessionFile, new: SessionFile, difftool: DifftoolContext, change: Change) {
    self.init(old: .file(old), new: .file(new), difftool: difftool, change: change)
  }

  /// Creates the description of a file of a comparison of folders whose sides are `old` and
  /// `new`, to which `change` happened.
  init(old: Side, new: Side, difftool: DifftoolContext, change: Change) {
    oldSide = old
    newSide = new
    self.difftool = difftool
    self.change = change
  }

  /// A side of a file.
  ///
  /// A comparison of folders lists many files; a side kept as a path below the shared top of its
  /// folder takes a fraction of the memory of a URL of its own, which is made only when asked
  /// for.
  enum Side: Sendable, Hashable {
    /// A file as it is, with its label.
    case file(SessionFile)

    /// The file at `path` below `folder`, labelled as the list labels it.
    case entry(folder: URL, path: String)

    /// No file: `/dev/null`, for a side of a new or deleted file.
    static let missing = Side.file(SessionFile(url: URL(filePath: "/dev/null"), label: ""))

    /// The side as a file, labelled `label` unless it has a label of its own.
    func file(label: String) -> SessionFile {
      switch self {
      case .file(let file):
        file.label.isEmpty ? SessionFile(url: file.url, label: label) : file
      case .entry(let folder, let path):
        SessionFile(url: URL(filePath: path, relativeTo: folder), label: label)
      }
    }
  }

  /// The path of the file in the repository, which the list and the title show.
  public var path: String {
    difftool.path
  }

  /// The number Git gave the file in its run, counted from 1, if it did.
  var number: Int? {
    difftool.filePosition?.number
  }

  /// Whether the file comes before `other` in the list: in the order of Git where both have a
  /// number, else by path as the Finder sorts names.
  func precedes(_ other: CollectedFile) -> Bool {
    if let number, let otherNumber = other.number, number != otherNumber {
      return number < otherNumber
    }
    return path.localizedStandardCompare(other.path) == .orderedAscending
  }
}
