import Dispatch
import Foundation
import Synchronization
import os

/// Tells when a file may have changed on disk: written in place, replaced by another file as
/// editors save atomically, removed, or put back.
///
/// The watcher observes the file and the folder that holds it. It tells more often than the
/// file changes, such as when another file of the folder changes, and never says what changed;
/// whoever it tells reads the file and compares. It stops when it is released.
final class FileWatcher: Sendable {
  /// The file watched.
  let url: URL

  private let path: String
  private let folderPath: String
  private let onChange: @MainActor @Sendable () -> Void
  private let queue = DispatchQueue(label: "app.eiden.seamerge.file-watcher")
  private let sources = Mutex(Sources())

  private struct Sources {
    var file: (any DispatchSourceFileSystemObject)?
    var fileIdentity: FileIdentity?
    var folder: (any DispatchSourceFileSystemObject)?
    var isStopped = false
  }

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// Watches the file at `url` from now on and calls `onChange` on the main actor whenever it
  /// may have changed.
  init(url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
    self.url = url
    path = url.path(percentEncoded: false)
    folderPath = url.deletingLastPathComponent().path(percentEncoded: false)
    self.onChange = onChange
    // At once, so that every change after this returns is told.
    queue.sync {
      watchFolder()
      watchFile()
    }
  }

  deinit {
    sources.withLock { sources in
      sources.isStopped = true
      sources.file?.cancel()
      sources.folder?.cancel()
    }
  }

  /// Watches the file that is at the path now, unless it is the one watched already.
  private func watchFile() {
    let identity = FileIdentity(path: path)
    let isWatched = sources.withLock { $0.file != nil && $0.fileIdentity == identity }
    guard !isWatched else { return }
    let source = identity.flatMap { _ in
      makeSource(path: path, mask: [.write, .extend, .delete, .rename, .attrib])
    }
    sources.withLock { sources in
      sources.file?.cancel()
      guard !sources.isStopped else {
        // Dispatch does not release a source that was never activated.
        source?.activate()
        source?.cancel()
        return
      }
      sources.file = source
      sources.fileIdentity = source == nil ? nil : identity
    }
    source?.activate()
  }

  private func watchFolder() {
    guard let source = makeSource(path: folderPath, mask: [.write, .rename, .delete]) else {
      Self.logger.notice("Cannot watch the folder \(self.folderPath, privacy: .public)")
      return
    }
    sources.withLock { sources in
      guard !sources.isStopped else {
        source.activate()
        source.cancel()
        return
      }
      sources.folder = source
    }
    source.activate()
  }

  /// A source for the events of `mask` on the file or folder at `path`, or `nil` if nothing is
  /// there.
  private func makeSource(
    path: String, mask: DispatchSource.FileSystemEvent
  ) -> (any DispatchSourceFileSystemObject)? {
    let descriptor = open(path, O_EVTONLY)
    guard descriptor >= 0 else { return nil }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor, eventMask: mask, queue: queue)
    source.setEventHandler { [weak self] in
      self?.somethingChanged()
    }
    source.setCancelHandler {
      close(descriptor)
    }
    return source
  }

  /// Follows the file to whatever is at its path now and tells that it may have changed.
  private func somethingChanged() {
    watchFile()
    let onChange = onChange
    Task { @MainActor in onChange() }
  }
}

/// What tells a file apart from another one at the same path.
private struct FileIdentity: Sendable, Equatable {
  let device: dev_t
  let inode: ino_t

  /// The identity of the file at `path`, or `nil` if there is none.
  init?(path: String) {
    var status = stat()
    guard stat(path, &status) == 0 else { return nil }
    device = status.st_dev
    inode = status.st_ino
  }
}
