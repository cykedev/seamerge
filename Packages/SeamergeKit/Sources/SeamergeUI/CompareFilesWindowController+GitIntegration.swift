import AppKit
import os

/// The line about Git at the bottom of the window and the sheet Set Up Git Integration.
extension CompareFilesWindowController {
  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "CompareFiles")

  /// The line about Git at the bottom of the window, below a separator, with its button at the
  /// trailing edge.
  func addGitStatusRow(to content: NSView) {
    let separator = NSBox()
    separator.boxType = .separator
    gitStatusLabel.lineBreakMode = .byTruncatingMiddle
    gitStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let row = NSStackView(views: [gitStatusLabel, NSView(), gitSetUpButton])
    row.distribution = .fill
    row.edgeInsets = NSEdgeInsets(
      top: 0, left: CompareFilesMetrics.margin, bottom: 0, right: CompareFilesMetrics.margin)
    for view in [separator, row] {
      view.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(view)
    }
    NSLayoutConstraint.activate([
      separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      separator.bottomAnchor.constraint(
        equalTo: content.bottomAnchor, constant: -CompareFilesMetrics.gitStatusHeight),
      row.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      row.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      row.topAnchor.constraint(equalTo: separator.bottomAnchor),
      row.bottomAnchor.constraint(equalTo: content.bottomAnchor),
    ])
  }

  /// Whether Set Up Git Integration… can be chosen: until Git is known to be missing.
  public var canSetUpGitIntegration: Bool {
    integrationStore != nil && (integrationStatus.map { $0.gitState != nil } ?? true)
  }

  /// Shows the window and on it the sheet Set Up Git Integration, once the settings are read.
  @objc public func showGitIntegration(_ sender: Any?) {
    guard integrationSheet == nil, integrationStore != nil else { return }
    if window?.isVisible != true {
      showWindow(sender)
    }
    Task { await presentGitIntegration() }
  }

  /// Reads the settings and shows the sheet Set Up Git Integration on the window, unless Git is
  /// missing.
  func presentGitIntegration() async {
    await readIntegrationStatus()
    presentIntegrationSheet()
  }

  /// Reads the settings of Git and Tower and shows on the line what they say.
  func readIntegrationStatus() async {
    guard let integrationStore else { return }
    do {
      integrationStatus = try await integrationStore.status()
    } catch {
      Self.logger.error("Cannot read the settings of Git: \(String(describing: error))")
    }
    showIntegrationStatus()
  }

  private func showIntegrationStatus() {
    gitStatusLabel.stringValue = integrationStatus?.line ?? ""
    gitSetUpButton.isHidden = integrationStatus?.offersSetUp != true
  }

  private func presentIntegrationSheet() {
    guard
      integrationSheet == nil, let window, let integrationStore, let integrationStatus,
      integrationStatus.gitState != nil
    else { return }
    let sheet = GitIntegrationSheet(
      status: integrationStatus, colors: CompareFilesColors(displayOptions))
    sheet.onConfirm = { [weak self] action in
      do throws(IntegrationFailure) {
        switch action {
        case .setUp(let addingToTower):
          try await integrationStore.setUp(addingToTower: addingToTower)
        case .addToTower: try await integrationStore.addToTower()
        case .remove: try await integrationStore.remove()
        }
      } catch {
        return error
      }
      await self?.readIntegrationStatus()
      return nil
    }
    sheet.onEnd = { [weak self, weak sheet] changed in
      guard let self, let sheetWindow = sheet?.window else { return }
      window.endSheet(sheetWindow)
      integrationSheet = nil
      if changed {
        announce(gitStatusLabel.stringValue)
      }
    }
    integrationSheet = sheet
    if let sheetWindow = sheet.window {
      window.beginSheet(sheetWindow)
    }
  }
}
