import CoreServices
import Foundation
import Synchronization
import os

/// Tells which entries changed below the tops of folders, through the file system events of
/// macOS.
///
/// The watcher reports each entry that was created, removed, renamed or written, a folder as a
/// whole where the system lost track of what inside it changed. It stops when it is released.
/// Folders on a volume without file system events, such as some network volumes, report nothing.
final class FolderWatcher: Sendable {
  /// An entry that changed, by its path from the root of the file system.
  struct Change: Sendable, Equatable {
    /// The path of the entry.
    let path: String

    /// Whether everything below the entry has to be looked at again: it is a folder that came,
    /// went or was renamed, or the system could not tell what changed inside it.
    let coversContents: Bool

    /// Whether the entry is a folder whose own attributes changed, which says nothing about the
    /// entries inside it.
    var isFolderAlone: Bool { isFolder && !coversContents }

    fileprivate let isFolder: Bool
  }

  private let stream: Mutex<FSEventStreamRef?>
  private let handler: Handler
  private let queue = DispatchQueue(label: "app.eiden.seamerge.folder-watcher")

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// Watches the folders at `paths` for the changes since the event `since`, so that nothing that
  /// happened while their entries were read goes unnoticed, and calls `onChange` on the main
  /// actor with the changes of every `latency`; `nil` if the system refuses.
  init?(
    paths: [String], since: FSEventStreamEventId, latency: Duration,
    onChange: @escaping @MainActor @Sendable ([Change]) -> Void
  ) {
    handler = Handler(onChange: onChange)
    var context = FSEventStreamContext(
      version: 0, info: Unmanaged.passUnretained(handler).toOpaque(), retain: nil, release: nil,
      copyDescription: nil)
    let flags = FSEventStreamCreateFlags(
      kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
        | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
    let seconds =
      CFTimeInterval(latency.components.seconds)
      + CFTimeInterval(latency.components.attoseconds) / 1e18
    guard
      let stream = FSEventStreamCreate(
        nil, Self.callback, &context, paths as CFArray, since, seconds, flags)
    else {
      Self.logger.error("Cannot watch the compared folders")
      return nil
    }
    FSEventStreamSetDispatchQueue(stream, queue)
    guard FSEventStreamStart(stream) else {
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      Self.logger.error("Cannot start watching the compared folders")
      return nil
    }
    self.stream = Mutex(stream)
  }

  deinit {
    // On the queue of the stream, so that no callback runs while the stream stops, and none
    // comes after; only then may the handler go.
    queue.sync {
      stream.withLock { stream in
        guard let watched = stream else { return }
        FSEventStreamStop(watched)
        FSEventStreamInvalidate(watched)
        FSEventStreamRelease(watched)
        stream = nil
      }
    }
  }

  /// The number of the latest event of the system, from which a watcher started later reports.
  static var currentEvent: FSEventStreamEventId {
    FSEventsGetCurrentEventId()
  }

  /// Hands the events of the stream to the handler; it runs on the queue of the stream, on which
  /// the watcher also stops the stream before it releases the handler.
  private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
    guard let info else { return }
    let handler = Unmanaged<Handler>.fromOpaque(info).takeUnretainedValue()
    let names = unsafeBitCast(paths, to: NSArray.self)
    var changes: [Change] = []
    for index in 0..<count {
      guard let path = names[index] as? String else { continue }
      changes.append(Change(path: path, flags: flags[index]))
    }
    handler.handle(changes)
  }

  /// Takes the changes from the queue of the stream to the main actor.
  private final class Handler: Sendable {
    private let onChange: @MainActor @Sendable ([Change]) -> Void

    init(onChange: @escaping @MainActor @Sendable ([Change]) -> Void) {
      self.onChange = onChange
    }

    func handle(_ changes: [Change]) {
      guard !changes.isEmpty else { return }
      let onChange = onChange
      Task { @MainActor in onChange(changes) }
    }
  }
}

extension FolderWatcher.Change {
  /// The change of the entry at `path`, as the `flags` of its event describe it.
  fileprivate init(path: String, flags: FSEventStreamEventFlags) {
    let has = { (flag: Int) in flags & FSEventStreamEventFlags(flag) != 0 }
    let isFolder = has(kFSEventStreamEventFlagItemIsDir)
    let isMoved =
      has(kFSEventStreamEventFlagItemCreated) || has(kFSEventStreamEventFlagItemRemoved)
      || has(kFSEventStreamEventFlagItemRenamed)
      || has(kFSEventStreamEventFlagItemChangeOwner)
      || has(kFSEventStreamEventFlagItemInodeMetaMod)
    let isLost =
      has(kFSEventStreamEventFlagMustScanSubDirs) || has(kFSEventStreamEventFlagRootChanged)
      || has(kFSEventStreamEventFlagUserDropped) || has(kFSEventStreamEventFlagKernelDropped)
    self.init(path: path, coversContents: isLost || (isFolder && isMoved), isFolder: isFolder)
  }
}
