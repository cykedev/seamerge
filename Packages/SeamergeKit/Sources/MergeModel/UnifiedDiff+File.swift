import Foundation
import TextIO

extension UnifiedDiff {
  /// One file of a unified diff: its older and its newer side, and how the headers name them.
  public struct File: Sendable {
    /// A side of a file.
    public enum Side: Sendable {
      /// The file does not exist on this side, as before it was added or after it was deleted;
      /// the headers call the side `/dev/null`.
      case missing

      /// The file as read.
      case file(SourceFile)

      /// The file exists but could not be read, so that it counts as one that differs.
      case unreadable
    }

    /// The older side, from which the patch leads.
    public var old: Side

    /// The newer side, to which the patch leads.
    public var new: Side

    /// How the headers name the sides.
    public var names: Names

    /// Describes a file whose older side is `old` and whose newer side is `new`.
    public init(old: Side, new: Side, names: Names) {
      self.old = old
      self.new = new
      self.names = names
    }

    /// Whether the diff has anything to say about the file: its sides hold other bytes, one of
    /// them is missing, or one cannot be read.
    ///
    /// A missing side counts as an empty file where the headers name no path: without the line
    /// `diff --git`, a diff cannot tell that a file without lines was added or deleted.
    public var hasChanges: Bool {
      switch (old, new) {
      case (.missing, .missing):
        false
      case (.file(let old), .file(let new)):
        old.bytes != new.bytes
      case (.missing, .file(let file)), (.file(let file), .missing):
        if case .labels = names { !file.bytes.isEmpty } else { true }
      default:
        true
      }
    }

    /// Whether the diff shows the lines of the file, rather than only that it differs, as for a
    /// binary file or one in UTF-16 or UTF-32.
    ///
    /// A file too large to compare shows no lines either, which only writing the diff finds out.
    public var showsLines: Bool {
      old.textFile != nil && new.textFile != nil
    }
  }

  /// How the headers of a file name its sides.
  public enum Names: Sendable, Hashable {
    /// Both sides are the file at a path below the top of a repository or a folder, which the
    /// headers write as `a/<path>` and `b/<path>` after a line `diff --git`.
    case path(String)

    /// The sides have names of their own, which the headers write as they are.
    case labels(old: String, new: String)

    /// The name of the older side, quoted as Git quotes it.
    var old: String {
      switch self {
      case .path(let path): GitQuotedName.quoted(path, prefix: "a/")
      case .labels(let old, _): GitQuotedName.quoted(old)
      }
    }

    /// The name of the newer side, quoted as Git quotes it.
    var new: String {
      switch self {
      case .path(let path): GitQuotedName.quoted(path, prefix: "b/")
      case .labels(_, let new): GitQuotedName.quoted(new)
      }
    }
  }
}

extension UnifiedDiff.File.Side {
  /// Whether the file does not exist on this side.
  public var isMissing: Bool {
    if case .missing = self { true } else { false }
  }

  /// The bytes and the encoding of the side, if the diff can show its lines: empty for a missing
  /// side, `nil` for a side that cannot be read, is binary, or is in UTF-16 or UTF-32, whose
  /// lines are not lines of bytes.
  var textFile: UnifiedDiff.TextFile? {
    switch self {
    case .missing:
      return UnifiedDiff.TextFile(bytes: Data(), encoding: nil)
    case .unreadable:
      return nil
    case .file(let file):
      switch file.encoding {
      case .utf8, .windows1252, .isoLatin1, .macRoman:
        return UnifiedDiff.TextFile(bytes: file.bytes, encoding: file.encoding)
      case .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian, nil:
        return nil
      }
    }
  }
}
