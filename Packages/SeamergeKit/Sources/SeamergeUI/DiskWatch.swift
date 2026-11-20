import Foundation

/// Watches the files of a session window on disk and has its delegate reload them once they may
/// have changed: once for every burst of changes, and once more after the window was busy.
///
/// The watch never reads a file. It tells its delegate when to look, remembers the bytes the
/// window has seen of each file, and holds back while the window reloads, saves or compares;
/// a change that arrives meanwhile is looked at once the window calls ``lookAgainIfAsked()``.
@MainActor
final class DiskWatch {
  /// Whether a window can reload its files now.
  enum Readiness {
    /// It shows files that it can reload.
    case ready

    /// It works with its files, as while it saves or compares them; it looks at them afterwards.
    case busy

    /// It has no files to reload: it closed, or shows why its files cannot be compared.
    case nothingToReload
  }

  /// Tells whether the window can reload its files, and reloads them.
  weak var delegate: (any DiskWatchDelegate)?

  private var watchers: [FileWatcher] = []

  /// Whether a look at the files is on its way, which the changes that arrive before it join.
  private var isLookPending = false

  /// Whether the delegate reloads the files now.
  private(set) var isReloading = false

  /// Whether the files may have changed while the window was busy.
  private var looksAgainOnceFree = false

  /// The bytes of each file that the window has seen, reloaded or not.
  private var seenBytes: [URL: Data] = [:]

  /// The files watched, in the order they were given.
  var watchedURLs: [URL] {
    watchers.map(\.url)
  }

  /// Watches the files at `urls`, each once; files watched already go on being watched.
  func watch(_ urls: [URL]) {
    let unique = urls.reduce(into: [URL]()) { unique, url in
      if !unique.contains(url) {
        unique.append(url)
      }
    }
    guard unique != watchedURLs else { return }
    watchers = unique.map { url in
      FileWatcher(url: url) { [weak self] in self?.filesMayHaveChanged() }
    }
  }

  /// Stops watching, as the window closes.
  func stop() {
    watchers = []
  }

  /// Looks at the files soon, once for every change that arrives before; the watchers of the
  /// files call it whenever one of them may have changed.
  func filesMayHaveChanged() {
    guard let delegate, !isLookPending,
      delegate.readinessToReload(for: self) != .nothingToReload
    else { return }
    isLookPending = true
    Task { await reloadChangedFiles() }
  }

  /// Has the delegate reload what changed on disk, unless the window has nothing to reload;
  /// while it reloads or is busy otherwise, it looks again once it is free.
  func reloadChangedFiles() async {
    isLookPending = false
    guard let delegate else { return }
    switch delegate.readinessToReload(for: self) {
    case .nothingToReload:
      return
    case .busy:
      looksAgainOnceFree = true
      return
    case .ready:
      guard !isReloading else {
        looksAgainOnceFree = true
        return
      }
    }
    isReloading = true
    defer {
      isReloading = false
      lookAgainIfAsked()
    }
    await delegate.reloadChangedFiles(for: self)
  }

  /// Looks at the files once more if they may have changed while the window was busy; the window
  /// calls it whenever it is done with what kept it busy.
  func lookAgainIfAsked() {
    guard looksAgainOnceFree else { return }
    looksAgainOnceFree = false
    filesMayHaveChanged()
  }

  /// Whether the window has seen `bytes` as the content of the file at `url` before, reloaded
  /// or not, so that it neither reloads nor asks about them again.
  func hasSeen(_ bytes: Data, at url: URL) -> Bool {
    seenBytes[url] == bytes
  }

  /// Notes that the window has seen `bytes` as the content of the file at `url`.
  func remember(_ bytes: Data, at url: URL) {
    seenBytes[url] = bytes
  }
}
