package import Foundation

/// Where the running copy of the app is, and whether Git can be pointed at it.
package struct AppLocation: Sendable, Equatable {
  /// Why Git cannot be pointed at this copy.
  package enum Problem: Sendable, Equatable {
    /// The command-line helper is missing from the bundle.
    case incomplete

    /// The copy runs from a place that may be gone tomorrow: a disk image, the Downloads folder,
    /// or a path macOS gives it for this launch only.
    case temporaryPlace
  }

  /// The bundle of the app.
  let bundle: URL

  /// The command-line helper inside the bundle, which Git runs.
  package var helper: URL { Self.helper(inBundle: bundle) }

  /// Why Git cannot be pointed at this copy, or `nil` if it can.
  let problem: Problem?

  /// Creates the location of the bundle at `bundle`.
  ///
  /// - Parameters:
  ///   - downloads: The Downloads folder of the user.
  ///   - isOnReadOnlyVolume: Whether the bundle is on a volume that cannot be written, as a
  ///     mounted disk image is.
  ///   - hasHelper: Whether the helper is in the bundle and can be run.
  init(bundle: URL, downloads: URL, isOnReadOnlyVolume: Bool, hasHelper: Bool) {
    self.bundle = bundle
    let path = bundle.standardizedFileURL.path
    let downloadsPath = downloads.standardizedFileURL.path
    if !hasHelper {
      problem = .incomplete
    } else if isOnReadOnlyVolume || path.contains("/AppTranslocation/")
      || path.hasPrefix(downloadsPath + "/")
    {
      problem = .temporaryPlace
    } else {
      problem = nil
    }
  }

  /// The command-line helper inside the app's bundle at `bundle`.
  package static func helper(inBundle bundle: URL) -> URL {
    bundle.appending(path: "Contents/Helpers/seamerge")
  }

  /// The location of the bundle at `bundle`, as the file system reports it.
  package static func current(bundle: URL) -> AppLocation {
    let isOnReadOnlyVolume: Bool
    do {
      isOnReadOnlyVolume =
        try bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly == true
    } catch {
      // A volume that does not say counts as writable; the other places are still recognized.
      isOnReadOnlyVolume = false
    }
    let downloads =
      FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
      ?? URL(filePath: NSHomeDirectory()).appending(path: "Downloads")
    let helper = helper(inBundle: bundle)
    return AppLocation(
      bundle: bundle, downloads: downloads, isOnReadOnlyVolume: isOnReadOnlyVolume,
      hasHelper: FileManager.default.isExecutableFile(atPath: helper.path))
  }
}
