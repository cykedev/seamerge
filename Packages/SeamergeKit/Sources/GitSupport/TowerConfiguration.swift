import Foundation

/// The entry that lists the tool among Tower's diff and merge tools.
///
/// Tower keeps a list of its own and does not read the tools of the Git configuration. It takes
/// further tools from a folder of its settings: `CompareTools.plist` lists them, each with a
/// script that Tower runs through `git difftool` and `git mergetool`, in the top folder of the
/// working tree, with the files as relative paths. The script gets `LOCAL REMOTE`, or
/// `LOCAL REMOTE MERGED` with the path of the file in the working tree, to compare, and
/// `LOCAL REMOTE BASE MERGED` to merge; Tower trusts its exit status. Adding keeps the other
/// entries of the list, and removing takes away only this one.
public struct TowerConfiguration: Sendable {
  /// What adding the entry would do in the folder.
  public enum Change: Sendable, Hashable {
    /// Creates `CompareTools.plist` and the script.
    case createsList

    /// Adds the entry to the `CompareTools.plist` there, which lists other tools, and creates
    /// the script.
    case addsToList

    /// Replaces the entry and the script of a copy of the tool that is not this one.
    case replacesEntry

    /// Renews the entry and the script of this copy, which an earlier version wrote.
    case updatesEntry
  }

  /// The files of the folder that adding the entry replaces, as they were.
  public struct Snapshot: Sendable, Hashable {
    /// The content of `CompareTools.plist`, or `nil` if there was none.
    let list: Data?

    /// The content of the script, or `nil` if there was none.
    let script: Data?
  }

  /// The folder Tower takes its further tools from.
  public let folder: URL

  /// The content of the script Tower runs, which hands the files to the helper.
  public let script: String

  /// The identifier of the entry in the list, which is also the name of the script.
  static let identifier = "seamerge"

  private var listURL: URL { folder.appending(path: "CompareTools.plist") }
  private var scriptURL: URL { folder.appending(path: "\(Self.identifier).sh") }

  /// Creates the entry for the helper at `helper` in `folder`.
  public init(helper: URL, folder: URL) {
    self.folder = folder
    let helperWord = GitConfiguration.shellQuoted(helper.path)
    // Tower passes the merged file of a merge as fourth argument, and the path of a compared
    // file as third, empty for the two folders of a directory diff. A comparison ends with 1
    // when the user closed its window before the rest of the run came; Git then ends the run
    // with an error, which Tower would report, so the script reports success instead. That
    // hides the other failures that end with 1 from Tower as well, such as a lost connection to
    // the app or a window the app cannot open; the helper still writes them to its error output.
    script = """
      #!/bin/sh
      # Opens a comparison or a merge from Tower in Seamerge.
      helper=\(helperWord)
      if [ "$#" -ge 4 ]; then
        exec "$helper" merge --from-git --base "$3" --local "$1" --remote "$2" --output "$4"
      elif [ "$#" -eq 3 ]; then
        "$helper" diff --collect --path "$3" -- "$1" "$2"
      else
        "$helper" diff --collect -- "$1" "$2"
      fi
      status=$?
      if [ "$status" -eq 1 ]; then
        exit 0
      fi
      exit "$status"

      """
  }

  /// The folder of Tower 3 and later in the home folder `home`.
  public static func folder(inHome home: URL) -> URL {
    home.appending(
      path: "Library/Application Support/com.fournova.Tower3/CompareTools",
      directoryHint: .isDirectory)
  }

  /// Whether the folder lists this copy of the tool.
  ///
  /// - Throws: ``TowerConfigurationError`` if the list or the script exists but cannot be read.
  public func isAdded() throws(TowerConfigurationError) -> Bool {
    guard try readList().contains(where: { Self.isOwn($0) && Self.isCurrent($0) }) else {
      return false
    }
    do {
      return try String(contentsOf: scriptURL, encoding: .utf8) == script
    } catch CocoaError.fileReadNoSuchFile {
      return false
    } catch {
      throw .unreadable(scriptURL, reason: error.localizedDescription)
    }
  }

  /// What adding the entry would do, or `nil` if this copy is listed already.
  ///
  /// - Throws: ``TowerConfigurationError`` if the list exists but cannot be read.
  public func change() throws(TowerConfigurationError) -> Change? {
    let list = try readList()
    if list.contains(where: Self.isOwn) {
      if try isAdded() { return nil }
      return try isOwnScript() ? .updatesEntry : .replacesEntry
    }
    return list.isEmpty ? .createsList : .addsToList
  }

  /// Lists the tool in the folder: writes its script and puts its entry in the list, after the
  /// entries of other tools, in place of an earlier entry of its own.
  ///
  /// - Throws: ``TowerConfigurationError`` if the list cannot be read or a file cannot be
  ///   written; a list that cannot be read stays as it is.
  public func add() throws(TowerConfigurationError) {
    let others = try readList().filter { !Self.isOwn($0) }
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try Data(script.utf8).write(to: scriptURL, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    } catch {
      throw .cannotWrite(scriptURL, reason: error.localizedDescription)
    }
    try writeList(others + [Self.entry])
  }

  /// Takes the tool out of the folder: its entry from the list, and its script.
  ///
  /// A list without other entries goes with them.
  ///
  /// - Throws: ``TowerConfigurationError`` if the list cannot be read or a file cannot be
  ///   changed.
  public func remove() throws(TowerConfigurationError) {
    let list = try readList()
    let others = list.filter { !Self.isOwn($0) }
    do {
      if others.isEmpty, FileManager.default.fileExists(atPath: listURL.path) {
        try FileManager.default.removeItem(at: listURL)
      }
      if FileManager.default.fileExists(atPath: scriptURL.path) {
        try FileManager.default.removeItem(at: scriptURL)
      }
    } catch {
      throw .cannotWrite(folder, reason: error.localizedDescription)
    }
    if !others.isEmpty, others.count != list.count {
      try writeList(others)
    }
  }

  /// The list and the script as they are now, to put back with ``restore(_:)``.
  ///
  /// - Throws: ``TowerConfigurationError`` if a file exists but cannot be read.
  public func snapshot() throws(TowerConfigurationError) -> Snapshot {
    Snapshot(list: try contents(of: listURL), script: try contents(of: scriptURL))
  }

  /// Puts the list and the script back as `snapshot` holds them: writes each file it holds and
  /// removes each it does not.
  ///
  /// - Throws: ``TowerConfigurationError`` if a file cannot be written or removed.
  public func restore(_ snapshot: Snapshot) throws(TowerConfigurationError) {
    for (url, data) in [(listURL, snapshot.list), (scriptURL, snapshot.script)] {
      do {
        if let data {
          try data.write(to: url, options: .atomic)
        } else if FileManager.default.fileExists(atPath: url.path) {
          try FileManager.default.removeItem(at: url)
        }
      } catch {
        throw .cannotWrite(url, reason: error.localizedDescription)
      }
    }
    if snapshot.script != nil {
      do {
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
      } catch {
        throw .cannotWrite(scriptURL, reason: error.localizedDescription)
      }
    }
  }

  /// The content of the file at `url`, or `nil` if there is none.
  private func contents(of url: URL) throws(TowerConfigurationError) -> Data? {
    do {
      return try Data(contentsOf: url)
    } catch CocoaError.fileReadNoSuchFile {
      return nil
    } catch {
      throw .unreadable(url, reason: error.localizedDescription)
    }
  }

  /// The entry of the tool in the list.
  private static var entry: [String: Any] {
    [
      "ApplicationIdentifier": "app.eiden.seamerge",
      "ApplicationName": "Seamerge",
      "DisplayName": "Seamerge",
      "Identifier": identifier,
      "LaunchScript": "\(identifier).sh",
      "SupportsMergeTool": true,
      // Tower then passes the path of a compared file, also between two commits.
      "SupportsDiffChangeset": true,
    ]
  }

  /// Whether `entry` is the entry this version writes.
  private static func isCurrent(_ entry: [String: Any]) -> Bool {
    NSDictionary(dictionary: entry).isEqual(to: Self.entry)
  }

  /// Whether the script in the folder hands the files to this copy of the helper, as one an
  /// earlier version wrote.
  private func isOwnScript() throws(TowerConfigurationError) -> Bool {
    let helperLine = script.split(separator: "\n").first { $0.hasPrefix("helper=") }
    do {
      let existing = try String(contentsOf: scriptURL, encoding: .utf8)
      return helperLine.map { existing.split(separator: "\n").contains($0) } ?? false
    } catch CocoaError.fileReadNoSuchFile {
      return false
    } catch {
      throw .unreadable(scriptURL, reason: error.localizedDescription)
    }
  }

  private static func isOwn(_ entry: [String: Any]) -> Bool {
    entry["Identifier"] as? String == identifier
  }

  /// The entries of the list, none if there is no list.
  private func readList() throws(TowerConfigurationError) -> [[String: Any]] {
    let data: Data
    do {
      data = try Data(contentsOf: listURL)
    } catch CocoaError.fileReadNoSuchFile {
      return []
    } catch {
      throw .unreadable(listURL, reason: error.localizedDescription)
    }
    let list: Any
    do {
      list = try PropertyListSerialization.propertyList(from: data, format: nil)
    } catch {
      throw .unreadable(listURL, reason: error.localizedDescription)
    }
    guard let entries = list as? [[String: Any]] else {
      throw .unreadable(listURL, reason: "It is not a list of tools.")
    }
    return entries
  }

  private func writeList(_ entries: [[String: Any]]) throws(TowerConfigurationError) {
    do {
      let data = try PropertyListSerialization.data(
        fromPropertyList: entries, format: .xml, options: 0)
      try data.write(to: listURL, options: .atomic)
    } catch {
      throw .cannotWrite(listURL, reason: error.localizedDescription)
    }
  }
}

/// An error in reading or writing Tower's list of tools.
public enum TowerConfigurationError: Error, Sendable, Hashable {
  /// The file at the URL exists but cannot be read, or is not a list of tools Tower could read.
  case unreadable(URL, reason: String)

  /// The file or folder at the URL could not be written.
  case cannotWrite(URL, reason: String)
}
