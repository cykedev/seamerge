import AppKit
import SeamergeUI

extension AppDelegate {
  /// Compares the files and folders selected in the Finder that the service Compare with
  /// Seamerge hands over on `pasteboard`, and brings the app to the front.
  ///
  /// The system calls this by the name `NSMessage` gives it in the information of the app.
  @objc func compareWithSeamerge(
    _ pasteboard: NSPasteboard, userData _: String?,
    error _: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    let objects = pasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    hasReceivedTask = true
    presenter.activate()
    let selection = ServiceSelection(objects as? [URL] ?? [])
    Task { await compare(selection) }
  }

  /// Does with `selection` what the service promises, beside any session that is open.
  ///
  /// Two files or two folders open at once and join the recent comparisons; if they cannot be
  /// opened, they stand in the window Compare Files with the reason, as if its button had failed
  /// to open them. Everything else goes into the window Compare Files.
  func compare(_ selection: ServiceSelection) async {
    switch selection {
    case .one(let entry):
      compareFiles().compare(with: entry)
    case .threeFiles(let files):
      compareFiles().show(replacingFilesWith: files)
    case .unsupported:
      compareFiles().showUnsupportedSelection()
    case .comparison(let comparison):
      do {
        try await coordinator.open(comparison)
        recentComparisons.add(comparison)
      } catch {
        compareFiles().showFailure(error, opening: comparison)
      }
    }
  }

  /// Registers the service with the system when this copy runs from a folder of applications,
  /// so that the Finder offers it at once; a copy elsewhere, such as on a disk image, serves the
  /// service only while it runs.
  func registerServiceIfInstalled() {
    let folder = bundle.deletingLastPathComponent().standardizedFileURL.path
    let applicationFolders = FileManager.default.urls(
      for: .applicationDirectory, in: [.localDomainMask, .userDomainMask]
    ).map(\.standardizedFileURL.path)
    if applicationFolders.contains(folder) {
      updateServices()
    }
  }
}
