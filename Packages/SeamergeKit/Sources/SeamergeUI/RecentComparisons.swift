import Foundation
import os

/// The comparisons and merges last opened from the welcome window, newest first, each with the
/// time it was opened, which the window lists and File > Open Recent offers; comparisons of
/// folders among them.
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

  /// A comparison in the list and when it was opened.
  public struct Entry: Equatable, Sendable {
    /// The files or folders in their roles.
    public var comparison: FileComparison

    /// When the comparison was last opened; `nil` for one kept by a version that did not note
    /// the time.
    public var opened: Date?
  }

  /// The comparisons, newest first, whose files are all still there.
  public var comparisons: [FileComparison] {
    entries.map(\.comparison)
  }

  /// The comparisons, newest first, whose files are all still there, with when they were opened.
  public var entries: [Entry] {
    stored.filter { entry in
      entry.comparison.files.allSatisfy {
        FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
      }
    }
  }

  /// Puts `comparison`, opened at `date`, first, in place of an earlier entry of the same files
  /// in the same roles.
  public func add(_ comparison: FileComparison, openedAt date: Date = .now) {
    let entries =
      [Entry(comparison: comparison, opened: date)]
      + self.entries.filter { $0.comparison != comparison }
    store(Array(entries.prefix(Self.maximumCount)))
  }

  /// Removes every comparison.
  public func clear() {
    store([])
  }

  private var stored: [Entry] {
    guard let entries = defaults.array(forKey: Self.key) as? [[String: String]] else { return [] }
    return entries.compactMap { entry in
      guard let left = entry[Field.left], let right = entry[Field.right] else {
        Self.logger.error("Skipping a recent comparison without both sides")
        return nil
      }
      let opened = entry[Field.opened].flatMap { try? Date($0, strategy: .iso8601) }
      if entry[Field.folders] != nil {
        let folders = FolderPair(
          left: URL(filePath: left, directoryHint: .isDirectory),
          right: URL(filePath: right, directoryHint: .isDirectory))
        return Entry(comparison: FileComparison(folders: folders), opened: opened)
      }
      let comparison = FileComparison(
        left: URL(filePath: left), base: entry[Field.base].map { URL(filePath: $0) },
        right: URL(filePath: right))
      return Entry(comparison: comparison, opened: opened)
    }
  }

  private func store(_ entries: [Entry]) {
    let values = entries.map { entry in
      let comparison = entry.comparison
      var value = [
        Field.left: comparison.left.path(percentEncoded: false),
        Field.right: comparison.right.path(percentEncoded: false),
      ]
      value[Field.base] = comparison.base?.path(percentEncoded: false)
      value[Field.folders] = comparison.comparesFolders ? Field.folders : nil
      value[Field.opened] = entry.opened?.formatted(.iso8601)
      return value
    }
    defaults.set(values, forKey: Self.key)
    NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
  }

  private enum Field {
    static let left = "left"
    static let base = "base"
    static let right = "right"
    static let folders = "folders"
    static let opened = "opened"
  }
}
