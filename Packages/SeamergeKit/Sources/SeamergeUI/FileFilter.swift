import FolderCompare
import Foundation

/// Which files of a collection its list shows: those whose path holds the text typed in the
/// filter field, and identical files only on request.
struct FileFilter: Equatable {
  /// The text that the name or the folder of a file must contain, ignoring case and diacritics;
  /// empty for every file.
  var text = "" {
    didSet {
      folded = text.folding(options: Self.options, locale: nil)
      asciiBytes = folded.utf8.allSatisfy { $0 < 0x80 } ? Array(folded.utf8) : nil
    }
  }

  /// Whether files whose sides hold the same bytes are listed.
  var showsIdenticalFiles = false

  /// The text without case and diacritics.
  private var folded = ""

  /// The bytes of the folded text, lowercase, if it is ASCII alone, which most paths are too:
  /// such a path is searched byte by byte, many times faster than with the rules of Unicode.
  private var asciiBytes: [UInt8]? = []

  private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

  /// Whether the list shows `file`.
  func includes(_ file: CollectedFile) -> Bool {
    if file.change == .identical, !showsIdenticalFiles {
      return false
    }
    guard !folded.isEmpty else { return true }
    if let asciiBytes, let found = Self.asciiPath(file.path, contains: asciiBytes) {
      return found
    }
    return file.path.range(of: folded, options: Self.options) != nil
  }

  /// Whether the ASCII path `path` contains `bytes` ignoring case, or `nil` if the path is not
  /// ASCII alone or not stored in one piece.
  private static func asciiPath(_ path: String, contains bytes: [UInt8]) -> Bool? {
    let found = path.utf8.withContiguousStorageIfAvailable { haystack -> Bool? in
      bytes.withUnsafeBufferPointer { needle -> Bool? in
        var start = 0
        var isASCII = true
        while start < haystack.count {
          isASCII = isASCII && haystack[start] < 0x80
          start += 1
        }
        guard isASCII else { return nil }
        start = 0
        while start + needle.count <= haystack.count {
          var index = 0
          while index < needle.count, lowercase(haystack[start + index]) == needle[index] {
            index += 1
          }
          if index == needle.count {
            return true
          }
          start += 1
        }
        return false
      }
    }
    return found ?? nil
  }

  private static func lowercase(_ byte: UInt8) -> UInt8 {
    (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
  }

  static func == (left: FileFilter, right: FileFilter) -> Bool {
    left.text == right.text && left.showsIdenticalFiles == right.showsIdenticalFiles
  }
}
