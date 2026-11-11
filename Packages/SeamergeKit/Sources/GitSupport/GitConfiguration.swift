import Foundation

/// The entries of the global Git configuration that make the tool Git's mergetool and difftool.
///
/// The entries can be shown as `git config` commands for the user to copy, compared with the
/// current configuration, and written. Writing changes only these entries; entries of other tools
/// stay, so switching back means setting `merge.tool` and `diff.tool` again.
public struct GitConfiguration: Sendable {
  /// One entry of the configuration.
  public struct Entry: Sendable, Hashable {
    /// The key, such as `merge.tool`.
    public var key: String

    /// The value.
    public var value: String
  }

  /// An entry whose current value writing the configuration would replace.
  public struct Replacement: Sendable, Hashable {
    /// The key of the entry.
    public var key: String

    /// The value the entry has now.
    public var currentValue: String

    /// The value writing would give it.
    public var newValue: String
  }

  /// The entries, in the order they are written.
  public let entries: [Entry]

  /// Creates the configuration for the helper at `helper`.
  ///
  /// The commands Git runs pass the files as `git mergetool` and `git difftool` name them. Git
  /// runs them through the shell, so the path of the helper is quoted where it needs to be.
  public init(helper: URL) {
    let helperCommand = Self.shellQuoted(helper.path)
    let mergeCommand =
      #"\#(helperCommand) merge --base "$BASE" --local "$LOCAL" --remote "$REMOTE" "#
      + #"--output "$MERGED""#
    // Git passes a file of the working tree by its relative path, which may start with a dash,
    // so `--` ends the options before the files. In the merge, every file follows an option.
    let diffCommand = #"\#(helperCommand) diff --path "$MERGED" -- "$LOCAL" "$REMOTE""#
    let tool = "seamerge"
    entries = [
      Entry(key: "merge.tool", value: tool),
      Entry(key: "mergetool.\(tool).cmd", value: mergeCommand),
      Entry(key: "mergetool.\(tool).trustExitCode", value: "true"),
      Entry(key: "mergetool.prompt", value: "false"),
      Entry(key: "mergetool.keepBackup", value: "false"),
      Entry(key: "diff.tool", value: tool),
      Entry(key: "difftool.\(tool).cmd", value: diffCommand),
      Entry(key: "difftool.prompt", value: "false"),
      Entry(key: "difftool.trustExitCode", value: "true"),
    ]
  }

  /// The entries as `git config --global` commands for a shell, one per entry.
  public var commands: [String] {
    entries.map { "git config --global \($0.key) \(Self.shellQuoted($0.value))" }
  }

  /// The entries that writing would change, with their current values.
  ///
  /// An entry that does not exist yet, or already has its value, is not a replacement.
  ///
  /// - Throws: ``GitError`` if the global configuration cannot be read.
  public func replacements(using git: Git) throws(GitError) -> [Replacement] {
    var replacements: [Replacement] = []
    for entry in entries {
      if let current = try currentValue(of: entry.key, using: git), current != entry.value {
        replacements.append(
          Replacement(key: entry.key, currentValue: current, newValue: entry.value))
      }
    }
    return replacements
  }

  /// Writes the entries into the global configuration.
  ///
  /// An entry with several values gets the one value of the configuration.
  ///
  /// - Throws: ``GitError`` if an entry cannot be written. The entries before it are written.
  public func write(using git: Git) throws(GitError) {
    for entry in entries {
      _ = try git.run(["config", "--global", "--replace-all", entry.key, entry.value])
    }
  }

  /// The value of `key` in the global configuration, or `nil` if it has none.
  private func currentValue(of key: String, using git: Git) throws(GitError) -> String? {
    do {
      return try git.text(["config", "--global", "--get", key])
    } catch .failed(_, status: 1, _) {
      return nil
    }
  }

  /// `text` as one word for a POSIX shell: unchanged if it holds no character the shell treats
  /// specially, otherwise in single quotes.
  private static func shellQuoted(_ text: String) -> String {
    let plain = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+:,@%")
    if !text.isEmpty, text.unicodeScalars.allSatisfy(plain.contains) {
      return text
    }
    return "'" + text.replacing("'", with: #"'\''"#) + "'"
  }
}
