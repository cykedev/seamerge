import Foundation
import GitSupport

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
  }

  /// The older side, shown on the left; `/dev/null` for a new file.
  public var old: SessionFile

  /// The newer side, shown on the right; `/dev/null` for a deleted file.
  public var new: SessionFile

  /// The path of the file in the repository, what each side is and, from Git, the number of the
  /// file in its run.
  public var difftool: DifftoolContext

  /// Creates the description of a file of a collection.
  public init(old: SessionFile, new: SessionFile, difftool: DifftoolContext) {
    self.old = old
    self.new = new
    self.difftool = difftool
  }

  /// The path of the file in the repository, which the list and the title show.
  public var path: String {
    difftool.path
  }

  /// What happened to the file, as the missing side shows it.
  public var change: Change {
    if FileOrigin(url: old.url) == .missing { return .added }
    if FileOrigin(url: new.url) == .missing { return .deleted }
    return .modified
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
