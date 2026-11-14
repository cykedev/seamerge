import Foundation
import os

/// Makes the tool Git's mergetool and difftool, tells whether it is, and takes it back.
///
/// It reads what applies outside a repository, from the system and the global configuration,
/// and writes only the global configuration, and only the entries of ``GitConfiguration``.
/// Setting up remembers the values it replaces, so that removing restores them; a value the user
/// has changed since stays as it is.
public struct GitIntegration: Sendable {
  /// The entries this integration writes.
  public let configuration: GitConfiguration

  private let git: Git

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "GitSupport")

  /// The name of the tool in `merge.tool` and `diff.tool`.
  private static let tool = "seamerge"

  /// The keys of the names of the tools, which make Git use a tool.
  private static let toolKeys: Set<String> = ["merge.tool", "diff.tool"]

  /// The sections that hold how Git runs the tool, removed as a whole.
  private static let ownSections = ["mergetool.\(tool)", "difftool.\(tool)"]

  /// Creates the integration of the helper at `helper`, which reads and writes with `git`.
  public init(helper: URL, git: Git) {
    configuration = GitConfiguration(helper: helper)
    self.git = git
  }

  /// What the configuration says now.
  ///
  /// - Throws: ``GitError`` if the configuration cannot be read.
  public func state() throws(GitError) -> GitIntegrationState {
    func tool(for kind: String) throws(GitError) -> GitIntegrationState.Tool {
      guard let name = try effectiveValue(of: "\(kind).tool") else { return .none }
      guard name == Self.tool else { return .other(name) }
      let key = "\(kind)tool.\(Self.tool).cmd"
      let command = try effectiveValue(of: key)
      if command == configuration.entries.first(where: { $0.key == key })?.value {
        return .seamerge
      }
      return .movedSeamerge(helper: command.flatMap { GitConfiguration.firstWord(of: $0) } ?? "")
    }
    var changedSwitches: Set<GitIntegrationState.Switch> = []
    for (key, setting) in [
      ("mergetool.prompt", GitIntegrationState.Switch.prompt),
      ("difftool.prompt", .prompt), ("mergetool.keepBackup", .keepBackup),
    ] where try effectiveValue(of: key, type: "bool") != "false" {
      changedSwitches.insert(setting)
    }
    return GitIntegrationState(
      merge: try tool(for: "merge"), diff: try tool(for: "diff"),
      changedSwitches: changedSwitches)
  }

  /// Writes the entries into the global configuration and returns the values to restore when
  /// the integration is removed.
  ///
  /// An entry that already has the value of the integration keeps the value remembered for it
  /// in `earlier`, the memory of an earlier setup, so that setting up again does not forget what
  /// was there before. If an entry cannot be written, the entries written so far get their
  /// earlier values back.
  ///
  /// - Throws: ``GitError`` if the configuration cannot be read or an entry cannot be written.
  public func setUp(keeping earlier: GitBackup?) throws(GitError) -> GitBackup {
    var current: [String: String?] = [:]
    for entry in configuration.entries {
      current[entry.key] = try globalValue(of: entry.key)
    }
    var backup = GitBackup()
    for entry in configuration.entries where !Self.isOwn(entry.key) {
      let value = current[entry.key] ?? nil
      if value == entry.value, let remembered = earlier?.values[entry.key] {
        backup.values[entry.key] = remembered
      } else if value == entry.value, Self.toolKeys.contains(entry.key) {
        // An earlier copy of the tool, set up by hand: removing leaves no tool rather than a
        // name without a command.
        backup.values[entry.key] = .some(nil)
      } else {
        backup.values[entry.key] = value
      }
    }
    var written: [String] = []
    for entry in configuration.entries {
      do {
        try set(entry.key, to: entry.value)
        written.append(entry.key)
      } catch {
        for key in written.reversed() {
          do {
            try restore(key, to: current[key] ?? nil)
          } catch let undoError {
            Self.logger.error("Cannot restore \(key) after a failed setup: \(undoError)")
          }
        }
        throw error
      }
    }
    return backup
  }

  /// Takes the integration back.
  ///
  /// Each entry that still has the value of the integration gets the value in `backup` back, or
  /// loses its value if it had none. Without a backup, as after setting up by hand, only the
  /// names of the tools are removed and the general switches stay. The sections that say how
  /// Git runs the tool go in any case; entries the user has changed since stay.
  ///
  /// - Throws: ``GitError`` if the configuration cannot be read or written.
  public func remove(restoring backup: GitBackup?) throws(GitError) {
    for entry in configuration.entries where !Self.isOwn(entry.key) {
      guard try globalValue(of: entry.key) == entry.value else { continue }
      if let remembered = backup?.values[entry.key] {
        try restore(entry.key, to: remembered)
      } else if Self.toolKeys.contains(entry.key) {
        try restore(entry.key, to: nil)
      }
    }
    for section in Self.ownSections {
      do {
        _ = try git.run(["config", "--global", "--get-regexp", "^\(section)\\."])
      } catch .failed(_, status: 1, _) {
        continue
      }
      _ = try git.run(["config", "--global", "--remove-section", section])
    }
  }

  /// Whether `key` belongs to the sections of the tool itself, which nothing else uses.
  private static func isOwn(_ key: String) -> Bool {
    ownSections.contains { key.hasPrefix($0 + ".") }
  }

  private func set(_ key: String, to value: String) throws(GitError) {
    _ = try git.run(["config", "--global", "--replace-all", key, value])
  }

  /// Gives `key` the value `value`, or removes it if `value` is `nil`.
  private func restore(_ key: String, to value: String?) throws(GitError) {
    guard let value else {
      do {
        _ = try git.run(["config", "--global", "--unset-all", key])
      } catch .failed(_, status: 5, _) {
        // The key has no value already.
      }
      return
    }
    try set(key, to: value)
  }

  /// The value of `key` in the global configuration, or `nil` if it has none.
  private func globalValue(of key: String) throws(GitError) -> String? {
    try value(of: key, arguments: ["--global"])
  }

  /// The value of `key` outside a repository, from the system or the global configuration.
  private func effectiveValue(of key: String, type: String? = nil) throws(GitError) -> String? {
    try value(of: key, arguments: type.map { ["--type=\($0)"] } ?? [], in: URL(filePath: "/"))
  }

  private func value(
    of key: String, arguments: [String], in directory: URL? = nil
  ) throws(GitError) -> String? {
    do {
      return try git.text(["config"] + arguments + ["--get", key], in: directory)
    } catch .failed(_, status: 1, _) {
      return nil
    }
  }
}

/// What the configuration of Git says about the integration.
public struct GitIntegrationState: Sendable, Hashable {
  /// The tool Git uses for merges or for diffs.
  public enum Tool: Sendable, Hashable {
    /// No tool.
    case none

    /// This copy of Seamerge.
    case seamerge

    /// A copy of Seamerge whose helper is at `helper`, which is not this copy.
    case movedSeamerge(helper: String)

    /// Another tool, by the name Git knows it by.
    case other(String)
  }

  /// A general switch of `git mergetool` and `git difftool` that setting up turns off, which
  /// affects other tools too.
  public enum Switch: Sendable, Hashable {
    /// Git asks before it opens a tool.
    case prompt

    /// Git keeps a backup of a merged file with the extension `.orig`.
    case keepBackup
  }

  /// The tool of `git mergetool`.
  public var merge: Tool

  /// The tool of `git difftool`.
  public var diff: Tool

  /// The switches that are on now and that setting up would turn off.
  public var changedSwitches: Set<Switch>

  /// Creates a state.
  public init(merge: Tool, diff: Tool, changedSwitches: Set<Switch>) {
    self.merge = merge
    self.diff = diff
    self.changedSwitches = changedSwitches
  }
}

/// The values a setup of the integration replaced, to restore when it is removed.
public struct GitBackup: Sendable, Hashable, Codable {
  /// The earlier value of each key the setup wrote, or `nil` for a key that had none.
  ///
  /// A key that is missing was not remembered.
  public var values: [String: String?]

  /// Creates a backup of `values`.
  public init(values: [String: String?] = [:]) {
    self.values = values
  }

  /// The tools that removing the integration brings back, for merges and for diffs.
  public var restoredTools: (merge: String?, diff: String?) {
    (values["merge.tool"] ?? nil, values["diff.tool"] ?? nil)
  }
}
