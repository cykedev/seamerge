import Foundation

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
      case .path(let path): Self.quoted(path, prefix: "a/")
      case .labels(let old, _): Self.quoted(old, prefix: "")
      }
    }

    /// The name of the newer side, quoted as Git quotes it.
    var new: String {
      switch self {
      case .path(let path): Self.quoted(path, prefix: "b/")
      case .labels(_, let new): Self.quoted(new, prefix: "")
      }
    }

    /// `prefix` and `name` as Git writes them in a header: as they are, or within quotes with
    /// escapes where they hold a quote, a backslash, a control character or a byte outside ASCII.
    ///
    /// A space alone needs no quotes; the lines `---` and `+++` end such a name with a tab.
    static func quoted(_ name: String, prefix: String) -> String {
      let bytes = Array((prefix + name).utf8)
      guard bytes.contains(where: needsEscape) else { return prefix + name }
      let escaped = bytes.map { needsEscape($0) ? escape(of: $0) : String(Unicode.Scalar($0)) }
      return "\"" + escaped.joined() + "\""
    }

    /// The escape Git writes for `byte`: a letter for the usual control characters, a backslash
    /// before a quote or a backslash, three octal digits for any other byte.
    private static func escape(of byte: UInt8) -> String {
      switch byte {
      case 0x07: "\\a"
      case 0x08: "\\b"
      case 0x09: "\\t"
      case 0x0A: "\\n"
      case 0x0B: "\\v"
      case 0x0C: "\\f"
      case 0x0D: "\\r"
      case UInt8(ascii: "\""): "\\\""
      case UInt8(ascii: "\\"): "\\\\"
      default: "\\" + octal(byte)
      }
    }

    /// Whether Git writes `byte` of a name as an escape.
    private static func needsEscape(_ byte: UInt8) -> Bool {
      byte < 0x20 || byte >= 0x7F || byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "\\")
    }

    /// `byte` as three octal digits.
    private static func octal(_ byte: UInt8) -> String {
      let digits = String(byte, radix: 8)
      return String(repeating: "0", count: 3 - digits.count) + digits
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
