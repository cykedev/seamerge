public import Foundation
import TextIO

/// A file of a unified diff with the two sides that its hunks give: on the left the lines of
/// context and the removed ones, on the right the lines of context and the added ones.
///
/// A patch holds only the hunks, not the whole files, and nothing is read from disk to fill in
/// the rest. Where the patch passes over lines, before the first hunk and between two hunks,
/// both sides hold a placeholder line instead, the same on both, which a comparison of the sides
/// pairs up; a pane shows a bar in its place. Every other line keeps the number its file gives
/// it, as the headers of the hunks say.
///
/// The sides are text decoded in the encoding that the lines of the file are in, with their line
/// endings, CRLF too; a file whose patch has a last line without a line break ends without one.
public struct PatchFile: Sendable {
  /// One side of the file as the hunks give it.
  public struct Side: Sendable, Hashable {
    /// The lines of the hunks on this side, with the placeholder lines between them.
    public let text: String

    /// The number of each line of the patch on this side in its file, counted from 0; a
    /// placeholder line has the number of the last line it stands for, the line before the hunk
    /// that follows it.
    let lineNumbers: [Int32]

    /// The offset in the UTF-8 of ``text`` where each line of the patch starts.
    let lineStarts: [Int]

    /// The placeholder lines, in their order.
    let placeholders: [Placeholder]

    /// Whether the patch only says that the file differs, as for a binary file, so that the
    /// side holds no lines.
    public let isBinary: Bool
  }

  /// A placeholder line of a side and the number of lines it stands for.
  struct Placeholder: Sendable, Hashable {
    /// The line of the patch on the side, counted from 0.
    let line: Int

    /// The number of lines that the patch passes over there.
    let lineCount: Int
  }

  /// A run of lines that the patch passes over, and the placeholder line that stands for it on
  /// each side.
  struct Gap: Sendable, Hashable {
    /// The line of the patch on the left side that stands for the run, counted from 0.
    let oldLine: Int

    /// The line of the patch on the right side that stands for the run, counted from 0.
    let newLine: Int

    /// The number of lines that the run passes over.
    let lineCount: Int
  }

  /// The path of the older side, without the prefix `a/` of Git; `nil` for a file the patch adds.
  public let oldPath: String?

  /// The path of the newer side, without the prefix `b/` of Git; `nil` for a file the patch
  /// deletes.
  public let newPath: String?

  /// Whether the patch only says that the file differs, as for a binary file, or holds lines
  /// that are not text.
  var isBinary: Bool {
    old.isBinary
  }

  /// The older side, shown on the left.
  public let old: Side

  /// The newer side, shown on the right.
  public let new: Side

  /// The runs of lines that the patch passes over, in their order.
  var gaps: [Gap] {
    zip(old.placeholders, new.placeholders).map { old, new in
      Gap(oldLine: old.line, newLine: new.line, lineCount: new.lineCount)
    }
  }

  /// The files of the unified diff in `bytes`, in its order; none for a patch without changes.
  ///
  /// Reading takes time in proportion to the size of the patch, so a large one is best read off
  /// the main thread.
  ///
  /// - Throws: ``MergeModelError/unreadablePatch`` if `bytes` is not a unified diff of two sides
  ///   or a hunk does not hold the lines its header says.
  public static func files(in bytes: Data) throws(MergeModelError) -> [PatchFile] {
    let patch: Patch
    do {
      patch = try Patch(reading: bytes)
    } catch {
      throw .unreadablePatch
    }
    return patch.files.map { PatchFile($0, of: patch) }
  }

  private init(_ file: Patch.File, of patch: Patch) {
    oldPath = file.oldPath
    newPath = file.newPath
    let lines = file.hunks.flatMap(\.lines)
    var bytes = Data()
    bytes.reserveCapacity(lines.reduce(0) { $0 + $1.bytes.count })
    for line in lines {
      bytes.append(patch.content(of: line))
    }
    guard !file.isBinary, let encoding = Self.textEncoding(of: bytes) else {
      let empty = Side(text: "", lineNumbers: [], lineStarts: [], placeholders: [], isBinary: true)
      (old, new) = (empty, empty)
      return
    }
    var builder = SidesBuilder(
      placeholder: Self.placeholder(avoiding: lines, of: patch), encoding: encoding)
    for hunk in file.hunks {
      builder.add(hunk, of: patch)
    }
    (old, new) = (builder.old.side, builder.new.side)
  }

  /// The encoding the lines `bytes` of a file are in, or `nil` if they are not text that the
  /// sides can be lines of: binary, or in UTF-16 or UTF-32.
  private static func textEncoding(of bytes: Data) -> TextEncoding? {
    let loaded: LoadedFile
    do {
      loaded = try LoadedFile(bytes: bytes)
    } catch {
      preconditionFailure("Recognizing the encoding of bytes never fails: \(error)")
    }
    guard case .text(let text) = loaded.content else { return nil }
    switch text.encoding {
    case .utf8, .windows1252, .isoLatin1, .macRoman: return text.encoding
    case .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian: return nil
    }
  }

  /// The text of the placeholder lines of a file: a midline ellipsis, repeated until no line of
  /// the file reads the same, so that a comparison pairs the placeholders with each other alone.
  private static func placeholder(avoiding lines: [Patch.Line], of patch: Patch) -> String {
    let ellipsis = Array("\u{22EF}".utf8)
    var longest = 0
    for line in lines {
      var content = patch.content(of: line)[...]
      while let last = content.last, last == 0x0A || last == 0x0D { content = content.dropLast() }
      guard !content.isEmpty, content.count % ellipsis.count == 0 else { continue }
      let count = content.count / ellipsis.count
      if content.elementsEqual(Array(repeating: ellipsis, count: count).joined()) {
        longest = max(longest, count)
      }
    }
    return String(repeating: "\u{22EF}", count: longest + 1)
  }
}

/// Puts the two sides of a file together, hunk by hunk.
private struct SidesBuilder {
  /// One side as far as it is built.
  struct SideText {
    var text = ""
    var lineNumbers: [Int32] = []
    var lineStarts: [Int] = []
    var placeholders: [PatchFile.Placeholder] = []

    /// The length of the UTF-8 of ``text``.
    var length = 0

    /// The number in the file of the line after the last one added, counted from 0.
    var nextLine = 0

    var side: PatchFile.Side {
      PatchFile.Side(
        text: text, lineNumbers: lineNumbers, lineStarts: lineStarts, placeholders: placeholders,
        isBinary: false)
    }

    /// Adds a placeholder line, `text` with its line ending, that stands for `lineCount` lines
    /// before the line numbered `nextLine`.
    mutating func addPlaceholder(_ text: String, lineCount: Int, before nextLine: Int) {
      placeholders.append(PatchFile.Placeholder(line: lineNumbers.count, lineCount: lineCount))
      append(text, number: Int32(max(nextLine - 1, 0)))
    }

    /// Adds `lines`, the decoded lines of a hunk on this side, the first of which has the number
    /// `start` in the file.
    mutating func add(_ lines: [String], startingAt start: Int) {
      for (offset, line) in lines.enumerated() {
        append(line, number: Int32(start + offset))
      }
      nextLine = start + lines.count
    }

    /// The line ending of the last line added, or `nil` if it ends without one or there is none.
    private(set) var lastLineEnding: String?

    /// Appends `line` with its number, after a line feed if the text so far ends without a line
    /// break, as the last line of a hunk wrongly marked as the end of the file may.
    private mutating func append(_ line: String, number: Int32) {
      if !text.isEmpty && lastLineEnding == nil {
        text += "\n"
        length += 1
      }
      lineStarts.append(length)
      lineNumbers.append(number)
      text += line
      length += line.utf8.count
      lastLineEnding = Self.lineEnding(of: line)
    }

    /// The line ending of `line`, or `nil` if it ends without one.
    private static func lineEnding(of line: String) -> String? {
      let utf8 = line.utf8
      guard let last = utf8.last else { return nil }
      if last == 0x0D {
        return "\r"
      }
      guard last == 0x0A else { return nil }
      let end = utf8.index(before: utf8.endIndex)
      return end > utf8.startIndex && utf8[utf8.index(before: end)] == 0x0D ? "\r\n" : "\n"
    }
  }

  let placeholder: String
  let encoding: TextEncoding
  var old = SideText()
  var new = SideText()

  init(placeholder: String, encoding: TextEncoding) {
    self.placeholder = placeholder
    self.encoding = encoding
  }

  /// Adds the lines of `hunk`, after a placeholder line on both sides where the hunk does not
  /// follow on from the lines before it.
  mutating func add(_ hunk: Patch.Hunk, of patch: Patch) {
    let (oldStart, newStart) = (hunk.old.lines.lowerBound, hunk.new.lines.lowerBound)
    let skipped = max(oldStart - old.nextLine, newStart - new.nextLine)
    if skipped > 0 {
      // Both placeholders are the same bytes, so that a comparison in any mode pairs them; they
      // end as the first line after them that has a line ending, preferably on the left.
      let ending =
        hunk.lines.lazy.compactMap { Self.lineEnding(of: patch.content(of: $0)) }.first
        ?? old.lastLineEnding ?? "\n"
      old.addPlaceholder(placeholder + ending, lineCount: skipped, before: oldStart)
      new.addPlaceholder(placeholder + ending, lineCount: skipped, before: newStart)
    }
    old.add(decoded(hunk.lines.filter { $0.kind != .added }, of: patch), startingAt: oldStart)
    new.add(decoded(hunk.lines.filter { $0.kind != .removed }, of: patch), startingAt: newStart)
  }

  /// The line ending of `bytes`, a line of a patch, or `nil` if it ends without one.
  private static func lineEnding(of bytes: Data) -> String? {
    guard let last = bytes.last else { return nil }
    if last == 0x0D { return "\r" }
    guard last == 0x0A else { return nil }
    let isCRLF = bytes.count > 1 && bytes[bytes.index(bytes.endIndex, offsetBy: -2)] == 0x0D
    return isCRLF ? "\r\n" : "\n"
  }

  /// Each of `lines` decoded in the encoding of the file.
  ///
  /// The lines are decoded together, which is much faster than one by one, and split again at
  /// their line feeds; a line without one, which only the last line of a file has, gets one
  /// should a hunk wrongly put it elsewhere.
  private func decoded(_ lines: [Patch.Line], of patch: Patch) -> [String] {
    var bytes = Data()
    for (index, line) in lines.enumerated() {
      let content = patch.content(of: line)
      bytes.append(content)
      if index < lines.count - 1 && content.last != 0x0A {
        bytes.append(0x0A)
      }
    }
    let text: String
    do {
      guard case .text(let decoded) = try LoadedFile(bytes: bytes, encoding: encoding).content
      else {
        preconditionFailure("Bytes decoded in a given encoding are text")
      }
      text = decoded.text
    } catch {
      // The encoding was recognized from all lines of the file, and lines valid together are
      // valid apart; should they ever not be, the side shows replacement characters there.
      text = String(decoding: bytes, as: UTF8.self)
    }
    var split: [String] = []
    split.reserveCapacity(lines.count)
    var line = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
      line.append(scalar)
      if scalar == "\n" {
        split.append(String(line))
        line = String.UnicodeScalarView()
      }
    }
    if !line.isEmpty {
      split.append(String(line))
    }
    return split
  }
}
