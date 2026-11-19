public import AppKit

/// The seamerge command in Terminal: whether this copy of Seamerge has put its link into the
/// `PATH`, and the sheet that installs, updates or removes the link.
///
/// The link goes to `/usr/local/bin`, which is in the `PATH` from the start, and is changed
/// with the rights of an administrator through the dialog of macOS. A file at its place that is
/// not a link to Seamerge is never replaced or removed.
@MainActor
public final class CommandLineTool {
  private let location: () -> AppLocation
  private let place: CommandLinePlace
  private let shell: any AdministratorShell

  /// The sheet while it is shown.
  private(set) var sheet: CommandLineToolSheet?

  /// Creates the command of the app whose bundle is at `bundle`, with its link at `link` and
  /// Homebrew looked for in `homebrewPrefixes`.
  public convenience init(
    bundle: URL, link: URL = URL(filePath: "/usr/local/bin/seamerge"),
    homebrewPrefixes: [URL] = [URL(filePath: "/opt/homebrew"), URL(filePath: "/usr/local")]
  ) {
    self.init(
      location: { AppLocation.current(bundle: bundle) },
      place: CommandLinePlace(link: link, homebrewPrefixes: homebrewPrefixes),
      shell: AppleScriptShell.administrator)
  }

  /// Creates the command of the copy at the location that `location` reads, with its link and
  /// Homebrew at `place`, which changes the link through `shell`.
  init(
    location: @escaping () -> AppLocation, place: CommandLinePlace,
    shell: any AdministratorShell
  ) {
    self.location = location
    self.place = place
    self.shell = shell
  }

  /// What lies at the place of the command now.
  var status: CommandLineToolStatus {
    place.status(for: location())
  }

  /// Whether the link of this copy is installed, so that the command of the app menu offers to
  /// remove it.
  public var isInstalled: Bool {
    status.entry == .thisCopy
  }

  /// Shows the sheet on `window`, drawing with `colors`, and tells `announce` the new state once
  /// the sheet has changed the link.
  func presentSheet(
    on window: NSWindow, colors: CompareFilesColors, announce: @escaping (String) -> Void
  ) {
    guard sheet == nil else { return }
    let status = status
    let sheet = CommandLineToolSheet(status: status, colors: colors)
    sheet.onConfirm = { [shell] change in
      do throws(CommandLineToolFailure) {
        try await shell.run(
          change.script, arguments: [status.helper.path, status.link.path],
          prompt: status.dialogPrompt)
      } catch {
        return error
      }
      return nil
    }
    sheet.onEnd = { [weak self, weak window, weak sheet] change in
      guard let sheetWindow = sheet?.window else { return }
      window?.endSheet(sheetWindow)
      self?.sheet = nil
      if let change {
        announce(CommandLineToolStatus.announcement(after: change))
      }
    }
    self.sheet = sheet
    if let sheetWindow = sheet.window {
      window.beginSheet(sheetWindow)
    }
  }
}
