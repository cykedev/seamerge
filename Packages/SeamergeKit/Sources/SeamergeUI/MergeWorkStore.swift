import Foundation
import MergeModel
import os

/// The folder that keeps the work of unfinished merges, one file for each merge, named by its
/// key, so that a merge opened again finds its work.
///
/// Work lasts 30 days after it was captured, and the folder keeps at most the 100 newest; the
/// store removes the rest after each write and whenever asked, the oldest first. It never
/// touches a file it did not write: other files, files it cannot read and files of a format
/// version it does not know stay where they are and do not count. Every file operation runs on
/// the store's own executor, off the main actor and one after another.
///
/// The store writes the keys of each file in sorted order, so that the small fields, among them
/// the format version and the time of capture, come before the segments and the text. Dating a
/// file then takes only its head, however large the work.
actor MergeWorkStore {
  /// How long work is kept after it was captured.
  static let lifetime: TimeInterval = 30 * 24 * 60 * 60

  /// How many merges the folder keeps work for.
  static let capacity = 100

  /// The folder that holds a file for each merge.
  let folder: URL

  /// The current time, by which the age of work counts.
  private let now: @Sendable () -> Date

  /// How many bytes of a file hold its head; the head of the current format takes a few hundred,
  /// however many segments and however much text the work has.
  ///
  /// Every field that sorts before `segments` must stay small; a large one would push the
  /// segments past the head, so that no file could be dated and none would ever expire.
  static let headLength = 4_096

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// Creates a store in `folder`, which it creates when it first writes.
  ///
  /// - Parameter now: The clock by which the age of work counts.
  init(folder: URL, now: @escaping @Sendable () -> Date = { Date() }) {
    self.folder = folder
    self.now = now
  }

  /// The folder of the user: `Seamerge/Merges` in Application Support, because the work belongs
  /// to the user and the system may empty the caches.
  static var standardFolder: URL {
    URL.applicationSupportDirectory.appending(path: "Seamerge/Merges", directoryHint: .isDirectory)
  }

  /// Writes `work` in place of any earlier work of its merge, then removes expired work.
  ///
  /// The file is replaced atomically, so that a failure or a crash leaves the earlier work as it
  /// was.
  ///
  /// - Throws: ``MergeWorkStoreError/writingFailed(reason:)`` if the file cannot be written.
  func write(_ work: MergeWork) throws(MergeWorkStoreError) {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      let data = try encoder.encode(work)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try data.write(to: fileURL(for: work.key), options: .atomic)
    } catch {
      Self.logger.error("Cannot keep the work of a merge: \(error, privacy: .public)")
      throw .writingFailed(reason: error.localizedDescription)
    }
    removeExpired()
  }

  /// The work of the merge with `key`, or `nil` if there is none.
  ///
  /// - Throws: ``MergeWorkStoreError/unknownFormatVersion(_:)`` for work that another version of
  ///   the app wrote, or ``MergeWorkStoreError/unreadable(reason:)`` for a file that holds no work
  ///   of this merge; the file stays either way.
  func read(_ key: MergeKey) throws(MergeWorkStoreError) -> MergeWork? {
    let data: Data
    do {
      data = try Data(contentsOf: fileURL(for: key))
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return nil
    } catch {
      throw .unreadable(reason: error.localizedDescription)
    }
    let version = Self.head(of: data.prefix(Self.headLength))?.formatVersion
    guard version == MergeWork.formatVersion else {
      throw Self.versionError(in: data)
    }
    let work: MergeWork
    do {
      work = try JSONDecoder().decode(MergeWork.self, from: data)
    } catch {
      throw .unreadable(reason: error.localizedDescription)
    }
    guard work.key == key else { throw .unreadable(reason: "The file holds another merge.") }
    return work
  }

  /// Removes the work of the merge with `key`, if there is any.
  ///
  /// - Throws: ``MergeWorkStoreError/removingFailed(reason:)`` if the file stays.
  func remove(_ key: MergeKey) throws(MergeWorkStoreError) {
    do {
      try FileManager.default.removeItem(at: fileURL(for: key))
    } catch let error as CocoaError where error.code == .fileNoSuchFile {
      return
    } catch {
      Self.logger.error("Cannot remove the work of a merge: \(error, privacy: .public)")
      throw .removingFailed(reason: error.localizedDescription)
    }
  }

  /// Removes work captured longer than ``lifetime`` ago and all but the ``capacity`` newest, the
  /// oldest first.
  ///
  /// Only files named like work whose head shows work of this format version count; every other
  /// file stays.
  func removeExpired() {
    let urls: [URL]
    do {
      urls = try FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return
    } catch {
      Self.logger.error("Cannot list the work of merges: \(error, privacy: .public)")
      return
    }

    var files: [(url: URL, savedAt: Double)] = []
    for url in urls where url.pathExtension == "json" {
      guard MergeKey(rawValue: url.deletingPathExtension().lastPathComponent) != nil,
        let head = Self.head(ofFileAt: url), head.formatVersion == MergeWork.formatVersion
      else { continue }
      files.append((url, head.savedAt))
    }
    files.sort { $0.savedAt > $1.savedAt }

    let oldest = now().addingTimeInterval(-Self.lifetime).timeIntervalSinceReferenceDate
    for (index, file) in files.enumerated()
    where index >= Self.capacity || file.savedAt < oldest {
      do {
        try FileManager.default.removeItem(at: file.url)
      } catch {
        Self.logger.error("Cannot remove expired work: \(error, privacy: .public)")
      }
    }
  }

  /// The file of the work of the merge with `key`.
  private func fileURL(for key: MergeKey) -> URL {
    folder.appending(path: "\(key.rawValue).json", directoryHint: .notDirectory)
  }

  /// The head of the file at `url`, or `nil` if the file holds none that this version can read.
  private static func head(ofFileAt url: URL) -> FileHead? {
    do {
      let handle = try FileHandle(forReadingFrom: url)
      defer {
        do {
          try handle.close()
        } catch {
          logger.error("Cannot close a file of work: \(error, privacy: .public)")
        }
      }
      return head(of: try handle.read(upToCount: headLength) ?? Data())
    } catch {
      logger.error("Cannot read a file of work: \(error, privacy: .public)")
      return nil
    }
  }

  /// The head that the first bytes of a file hold: everything before the segments, which the
  /// sorted keys put after the small fields, as an object of its own; `nil` if there is none.
  ///
  /// It relies on the fields before `segments` fitting into ``headLength``.
  private static func head(of bytes: Data) -> FileHead? {
    guard let segments = bytes.firstRange(of: Data(#","segments":"#.utf8)) else { return nil }
    var object = Data(bytes[..<segments.lowerBound])
    object.append(UInt8(ascii: "}"))
    do {
      return try JSONDecoder().decode(FileHead.self, from: object)
    } catch {
      // Not the head of the current format; the caller treats the file as none of its own.
      return nil
    }
  }

  /// The error for a file whose head is not that of work of this format version: the version it
  /// names, if any, or that it is unreadable.
  ///
  /// This parses the whole file, which only a file that is no work of this version costs.
  private static func versionError(in data: Data) -> MergeWorkStoreError {
    do {
      let version = try JSONDecoder().decode(FormatVersion.self, from: data).formatVersion
      return version == MergeWork.formatVersion
        ? .unreadable(reason: "The file does not begin with the fields of its format.")
        : .unknownFormatVersion(version)
    } catch {
      return .unreadable(reason: error.localizedDescription)
    }
  }

  /// The fields at the head of a file of work of the current format version.
  private struct FileHead: Decodable {
    let formatVersion: Int

    /// The time of capture, in seconds since the reference date of `Date`.
    let savedAt: Double
  }

  /// The field that every format version has.
  private struct FormatVersion: Decodable {
    let formatVersion: Int
  }
}

/// Why the work of a merge could not be kept, read or removed.
enum MergeWorkStoreError: Error, Hashable {
  /// The file could not be written, for the reason the file system gives.
  case writingFailed(reason: String)

  /// The file holds no work of the merge in the format of this version of the app.
  case unreadable(reason: String)

  /// The file holds work in a format version that this version of the app does not know.
  case unknownFormatVersion(Int)

  /// The file could not be removed, for the reason the file system gives.
  case removingFailed(reason: String)
}
