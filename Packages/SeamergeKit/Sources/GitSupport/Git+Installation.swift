import Foundation

extension Git {
  /// A runner for the installed `git`, or `nil` if there is none.
  ///
  /// Without the developer tools, `/usr/bin/git` is a stand-in that asks the system to install
  /// them, and starting it opens that dialog. So a `git` other than `/usr/bin/git` on the search
  /// path counts as installed, and `/usr/bin/git` counts only if the developer directory holds
  /// the real one; the check never starts `git`.
  ///
  /// - Parameters:
  ///   - environment: The environment the commands run in. Its `PATH` decides which `git` runs,
  ///     and its `DEVELOPER_DIR`, if set, is the developer directory.
  ///   - timeout: How long a single command may take.
  public static func installed(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    timeout: Duration = .seconds(2)
  ) -> Git? {
    let git = Git(environment: environment, timeout: timeout)
    guard git.executableURL == standIn else { return git }
    guard
      let developerDirectory = environment["DEVELOPER_DIR"] ?? selectedDeveloperDirectory(),
      FileManager.default.isExecutableFile(
        atPath: URL(filePath: developerDirectory).appending(path: "usr/bin/git").path)
    else { return nil }
    return git
  }

  /// The `git` that stands in for the developer tools while they are missing.
  private static let standIn = URL(filePath: "/usr/bin/git")

  /// The developer directory that `xcode-select` has chosen, or `nil` if it has none.
  ///
  /// Unlike the tools it selects, `xcode-select` itself is part of the system and asks for
  /// nothing.
  private static func selectedDeveloperDirectory() -> String? {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/xcode-select")
    process.arguments = ["--print-path"]
    process.standardInput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let output = Pipe()
    process.standardOutput = output
    do {
      try process.run()
    } catch {
      return nil
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return path.isEmpty ? nil : path
  }
}
