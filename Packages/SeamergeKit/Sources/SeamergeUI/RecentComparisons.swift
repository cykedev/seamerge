import Foundation
import os

/// The comparisons and merges last opened from the window Compare Files, newest first, which the
/// window lists and File > Open Recent offers; comparisons of folders among them.
///
/// They are kept in the user defaults. A comparison whose files or folders are no longer all
/// there is left out. Sessions that Git starts never get here: their files are temporary copies.
@MainActor
public final class RecentComparisons {
  /// Posted, with the list as the object, after a comparison was added or the list cleared.
  public static let didChangeNotification = Notification.Name(
    "app.eiden.seamerge.RecentComparisonsDidChange")

  /// The most comparisons the list keeps.
  public static let maximumCount = 10

  private static let key = "RecentComparisons"
  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  private let defaults: UserDefaults

  /// Creates the list kept in `defaults`.
  public init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  /// The comparisons, newest first, whose files are all still there.
  public var comparisons: [FileComparison] {
    stored.filter { comparison in
      comparison.files.allSatisfy {
        FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
      }
    }
  }

  /// Puts `comparison` first, in place of an earlier entry of the same files in the same roles.
  public func add(_ comparison: FileComparison) {
    let comparisons = [comparison] + self.comparisons.filter { $0 != comparison }
    store(Array(comparisons.prefix(Self.maximumCount)))
  }

  /// Removes every comparison.
  public func clear() {
    store([])
  }

  private var stored: [FileComparison] {
    guard let entries = defaults.array(forKey: Self.key) as? [[String: String]] else { return [] }
    return entries.compactMap { entry in
      guard let left = entry[Field.left], let right = entry[Field.right] else {
        Self.logger.error("Skipping a recent comparison without both sides")
        return nil
      }
      if entry[Field.folders] != nil {
        return FileComparison(
          folders: FolderPair(
            left: URL(filePath: left, directoryHint: .isDirectory),
            right: URL(filePath: right, directoryHint: .isDirectory)))
      }
      return FileComparison(
        left: URL(filePath: left), base: entry[Field.base].map { URL(filePath: $0) },
        right: URL(filePath: right))
    }
  }

  private func store(_ comparisons: [FileComparison]) {
    let entries = comparisons.map { comparison in
      var entry = [
        Field.left: comparison.left.path(percentEncoded: false),
        Field.right: comparison.right.path(percentEncoded: false),
      ]
      entry[Field.base] = comparison.base?.path(percentEncoded: false)
      entry[Field.folders] = comparison.comparesFolders ? Field.folders : nil
      return entry
    }
    defaults.set(entries, forKey: Self.key)
    NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
  }

  private enum Field {
    static let left = "left"
    static let base = "base"
    static let right = "right"
    static let folders = "folders"
  }
}
