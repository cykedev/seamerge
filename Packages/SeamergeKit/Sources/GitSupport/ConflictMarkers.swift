import Foundation

/// The labels Git writes after the conflict markers of a merged file.
public struct ConflictMarkerLabels: Sendable, Hashable {
  /// The label after `<<<<<<<`, which names the local side.
  public var local: String?

  /// The label after `|||||||`, which names the base; only there in the `diff3` and `zdiff3`
  /// conflict styles.
  public var base: String?

  /// The label after `>>>>>>>`, which names the remote side.
  public var remote: String?

  /// Creates labels; a missing label is `nil`.
  public init(local: String?, base: String?, remote: String?) {
    self.local = local
    self.base = base
    self.remote = remote
  }
}

/// Reads the conflict markers Git writes into a file it could not merge.
public enum ConflictMarkers {
  /// The labels of the first complete conflict in `text`, or `nil` if there is none.
  ///
  /// A conflict is complete when a line starting with `<<<<<<<` is followed by a line `=======`
  /// and then by a line starting with `>>>>>>>`, optionally with a line starting with `|||||||`
  /// before the `=======`. A marker is exactly seven characters, followed by a space and the
  /// label or by the end of the line. Any line break ends a line, including a carriage return and a
  /// line feed. An empty label is `nil`.
  public static func labels(in text: String) -> ConflictMarkerLabels? {
    var conflict: ConflictMarkerLabels?
    var hasSeparator = false
    for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
      if let label = label(of: line, marker: "<<<<<<<") {
        conflict = ConflictMarkerLabels(local: label.nonEmpty, base: nil, remote: nil)
        hasSeparator = false
      } else if conflict == nil {
        continue
      } else if !hasSeparator, let label = label(of: line, marker: "|||||||") {
        conflict?.base = label.nonEmpty
      } else if !hasSeparator, line == "=======" {
        hasSeparator = true
      } else if hasSeparator, let label = label(of: line, marker: ">>>>>>>") {
        conflict?.remote = label.nonEmpty
        return conflict
      }
    }
    return nil
  }

  /// The labels of the first complete conflict in the file at `url`.
  ///
  /// The file is read in the encoding of its byte order mark, and as UTF-8 without one. Bytes
  /// that are not valid there only garble the labels they are in.
  ///
  /// - Throws: The error of the file system if the file cannot be read.
  static func labels(inContentsOf url: URL) throws -> ConflictMarkerLabels? {
    labels(in: decode(try Data(contentsOf: url, options: .mappedIfSafe)))
  }

  /// The label after `marker` at the start of `line`, which is empty for a marker alone, or
  /// `nil` if the line does not start with the marker.
  private static func label(of line: Substring, marker: String) -> String? {
    guard line.hasPrefix(marker) else { return nil }
    let rest = line.dropFirst(marker.count)
    guard rest.isEmpty || rest.first == " " else { return nil }
    return rest.trimmingCharacters(in: .whitespaces)
  }

  private static func decode(_ bytes: Data) -> String {
    let byteOrderMarks: [([UInt8], String.Encoding)] = [
      ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian),
      ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian),
      ([0xFF, 0xFE], .utf16LittleEndian),
      ([0xFE, 0xFF], .utf16BigEndian),
      ([0xEF, 0xBB, 0xBF], .utf8),
    ]
    for (mark, encoding) in byteOrderMarks where bytes.starts(with: mark) {
      if let text = String(data: bytes.dropFirst(mark.count), encoding: encoding) {
        return text
      }
    }
    return String(decoding: bytes, as: UTF8.self)
  }
}

extension String {
  /// The string, or `nil` if it is empty.
  fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
