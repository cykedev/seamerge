package import Foundation

extension Patch {
  /// Reads `bytes` as a unified diff: the files of `git diff` with their headers, or those of
  /// `diff -u`, one after the other.
  ///
  /// Lines before the first file and between files that no header names are passed over, such as
  /// the message of a commit that `git format-patch` writes. A file whose mode alone changes is
  /// left out. Text without any file is a patch without changes if it is empty or blank.
  ///
  /// Reading takes time in proportion to the size of the patch, so a large one is best read off
  /// the main thread.
  ///
  /// - Throws: ``PatchReadingError`` if the text is not a unified diff of two sides, or a hunk
  ///   does not hold the lines its header says.
  package init(reading bytes: Data) throws(PatchReadingError) {
    let bytes = bytes.startIndex == 0 ? bytes : Data(bytes)
    var reader = PatchReader(bytes: bytes)
    let files = try reader.readFiles()
    if files.isEmpty && !reader.namesFiles
      && bytes.contains(where: { !PatchReader.blanks.contains($0) })
    {
      throw .notUnifiedDiff
    }
    self.init(bytes: bytes, files: files)
  }
}

/// Reads the lines of a patch from the first to the last, once.
private struct PatchReader {
  /// The bytes that count as blank in a patch without files.
  static let blanks: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]

  private let bytes: Data

  /// The offset where each line starts, followed by the end of the bytes.
  private let lineStarts: [Int]

  /// Whether a header of a file has been read, even of one that is left out.
  private(set) var namesFiles = false

  init(bytes: Data) {
    self.bytes = bytes
    var starts = [0]
    bytes.withUnsafeBytes { buffer in
      guard let base = buffer.baseAddress else { return }
      var offset = 0
      while offset < buffer.count,
        let found = memchr(base + offset, Int32(Self.lineFeed), buffer.count - offset)
      {
        offset = base.distance(to: UnsafeRawPointer(found)) + 1
        starts.append(offset)
      }
    }
    if starts.last != bytes.count {
      starts.append(bytes.count)
    }
    lineStarts = starts
  }

  private var lineCount: Int { lineStarts.count - 1 }

  /// Reads every file of the patch.
  mutating func readFiles() throws(PatchReadingError) -> [Patch.File] {
    var files: [Patch.File] = []
    var current: FileHeader?
    var line = 0
    while line < lineCount {
      if hasPrefix(line, "diff --git ") {
        current.flatMap { $0.file }.map { files.append($0) }
        current = FileHeader(gitNames: try gitNames(line))
        namesFiles = true
        line += 1
      } else if hasPrefix(line, "diff --cc ") || hasPrefix(line, "diff --combined ")
        || hasPrefix(line, "@@@ ")
      {
        throw .combinedDiff(line: line + 1)
      } else if hasPrefix(line, "--- "), line + 1 < lineCount, hasPrefix(line + 1, "+++ ") {
        let names = (try fileName(line), try fileName(line + 1))
        if var header = current, header.takesNameLines {
          header.nameLines = names
          current = header
        } else {
          current.flatMap { $0.file }.map { files.append($0) }
          current = FileHeader(nameLines: names)
        }
        namesFiles = true
        line += 2
      } else if hasPrefix(line, "@@ ") {
        guard var header = current, header.nameLines != nil else {
          throw .hunkWithoutFile(line: line + 1)
        }
        let (hunk, next) = try readHunk(at: line)
        // Without the copy in `current`, the hunks grow in place rather than being copied for
        // each hunk.
        current = nil
        header.hunks.append(hunk)
        current = header
        if next < lineCount, isStrayLineOfHunk(next) {
          throw .hunkLengthMismatch(line: line + 1)
        }
        line = next
      } else if var header = current, header.takesExtendedHeaders {
        try read(extendedHeader: line, into: &header)
        current = header
        line += 1
      } else if let names = binaryNames(line) {
        current.flatMap { $0.file }.map { files.append($0) }
        current = nil
        FileHeader(binaryNames: names).file.map { files.append($0) }
        namesFiles = true
        line += 1
      } else {
        line += 1
      }
    }
    current.flatMap { $0.file }.map { files.append($0) }
    return files
  }

  /// Reads a line of the extended header of a file of Git, which comes between `diff --git` and
  /// the lines `---` and `+++`; a line that says nothing about the lines of the file is passed
  /// over.
  private func read(extendedHeader line: Int, into header: inout FileHeader)
    throws(PatchReadingError)
  {
    if hasPrefix(line, "new file mode ") {
      header.isAdded = true
    } else if hasPrefix(line, "deleted file mode ") {
      header.isDeleted = true
    } else if hasPrefix(line, "rename from ") || hasPrefix(line, "copy from ") {
      header.renamedFrom = try plainName(line, after: hasPrefix(line, "copy") ? 10 : 12)
    } else if hasPrefix(line, "rename to ") || hasPrefix(line, "copy to ") {
      header.renamedTo = try plainName(line, after: hasPrefix(line, "copy") ? 8 : 10)
    } else if hasPrefix(line, "GIT binary patch") || binaryNames(line) != nil {
      header.isBinary = true
    }
  }

  /// Reads the hunk whose header is at `line` and returns it with the line after it.
  private func readHunk(at line: Int) throws(PatchReadingError) -> (Patch.Hunk, next: Int) {
    let (old, new) = try hunkRanges(line)
    var (oldLeft, newLeft) = (old.count, new.count)
    var lines: [Patch.Line] = []
    lines.reserveCapacity(max(old.count, new.count))
    var next = line + 1
    while oldLeft > 0 || newLeft > 0 {
      guard next < lineCount else { throw .truncatedHunk(line: line + 1) }
      let start = lineStarts[next]
      let first = start < bytes.count ? bytes[start] : nil
      let kind: Patch.Line.Kind
      var content = start + 1..<lineStarts[next + 1]
      switch first {
      case Self.space where oldLeft > 0 && newLeft > 0:
        kind = .context
      case Self.lineFeed where oldLeft > 0 && newLeft > 0,
        Self.carriageReturn where oldLeft > 0 && newLeft > 0 && isBlank(next):
        // Some mail programs drop the space of an empty line of context; Git takes it back.
        kind = .context
        content = start..<lineStarts[next + 1]
      case Self.minus where oldLeft > 0:
        kind = .removed
      case Self.plus where newLeft > 0:
        kind = .added
      case Self.backslash where !lines.isEmpty:
        lines[lines.count - 1].dropLineFeed(in: bytes)
        next += 1
        continue
      case Self.space, Self.minus, Self.plus, Self.backslash:
        throw isFileHeader(next)
          ? .truncatedHunk(line: line + 1) : .hunkLengthMismatch(line: line + 1)
      default:
        throw .truncatedHunk(line: line + 1)
      }
      lines.append(Patch.Line(kind: kind, bytes: content))
      if kind != .added { oldLeft -= 1 }
      if kind != .removed { newLeft -= 1 }
      next += 1
    }
    while next < lineCount, firstByte(next) == Self.backslash, !lines.isEmpty {
      lines[lines.count - 1].dropLineFeed(in: bytes)
      next += 1
    }
    return (Patch.Hunk(old: old, new: new, lines: lines), next)
  }

  /// Whether `line`, right after a hunk, would have been a line of it: one that starts with a
  /// space, a plus or a minus but begins no file and is not the line `-- ` that ends the
  /// patches of `git format-patch`.
  private func isStrayLineOfHunk(_ line: Int) -> Bool {
    switch firstByte(line) {
    case Self.space, Self.plus:
      return true
    case Self.minus:
      let text = headerText(line)
      return !text.elementsEqual("-- ".utf8) && !text.elementsEqual("--".utf8)
        && !isFileHeader(line)
    default:
      return false
    }
  }

  /// Whether `line` starts the header of another file.
  private func isFileHeader(_ line: Int) -> Bool {
    hasPrefix(line, "diff ")
      || (hasPrefix(line, "--- ") && line + 1 < lineCount && hasPrefix(line + 1, "+++ "))
  }

  /// The ranges of the header of a hunk, `@@ -start[,count] +start[,count] @@`.
  private func hunkRanges(_ line: Int) throws(PatchReadingError) -> (
    old: Patch.LineRange, new: Patch.LineRange
  ) {
    var scanner = HeaderScanner(text: headerText(line)[3...])
    guard scanner.skip(Self.minus), let old = scanner.range(), scanner.skip(Self.space),
      scanner.skip(Self.plus), let new = scanner.range(), scanner.skip(Self.space),
      scanner.skip(UInt8(ascii: "@")), scanner.skip(UInt8(ascii: "@"))
    else {
      throw .malformedHunkHeader(line: line + 1)
    }
    return (old, new)
  }

  /// The names of the line `diff --git a/<old> b/<new>`, as written, prefixes included.
  private func gitNames(_ line: Int) throws(PatchReadingError) -> (old: String, new: String) {
    let text = headerText(line).dropFirst(11)
    if text.first == Self.quote {
      guard let (old, length) = GitQuotedName.unquoted(text) else {
        throw .malformedFileName(line: line + 1)
      }
      let rest = text.dropFirst(length + 1)
      return (Self.name(old), try name(of: rest, line: line))
    }
    if let quote = text.firstRange(of: [Self.space, Self.quote]) {
      let new = try name(of: text[(quote.lowerBound + 1)...], line: line)
      return (Self.name(text[..<quote.lowerBound]), new)
    }
    // Names without quotes may hold spaces. The sides of a file that keeps its name are the same
    // path behind prefixes of one letter, so the space between them stands in the middle.
    let middle = text.startIndex + text.count / 2
    let split: Int?
    if text.count % 2 == 1, text[middle] == Self.space,
      text[..<middle].dropFirst(2).elementsEqual(text[(middle + 1)...].dropFirst(2))
    {
      split = middle
    } else {
      split =
        text.indices.first { index in
          text[index] == Self.space && index + 2 < text.endIndex
            && FileHeader.prefixLetters.contains(text[index + 1]) && text[index + 2] == Self.slash
        } ?? text.firstIndex(of: Self.space)
    }
    guard let split else { return (Self.name(text), Self.name(text)) }
    return (Self.name(text[..<split]), Self.name(text[(split + 1)...]))
  }

  /// The name in the line `---` or `+++` at `line`: quoted as Git quotes names, or up to the tab
  /// before a date; `nil` for `/dev/null`.
  private func fileName(_ line: Int) throws(PatchReadingError) -> String? {
    let text = headerText(line).dropFirst(4)
    let name: String
    if text.first == Self.quote {
      guard let (bytes, _) = GitQuotedName.unquoted(text) else {
        throw .malformedFileName(line: line + 1)
      }
      name = Self.name(bytes)
    } else {
      name = Self.name(text.prefix { $0 != Self.tab })
    }
    return name == "/dev/null" ? nil : name
  }

  /// The name after the first `offset` bytes of `line`, such as after `rename from `: quoted as
  /// Git quotes names, or the rest of the line.
  private func plainName(_ line: Int, after offset: Int) throws(PatchReadingError) -> String {
    try name(of: headerText(line).dropFirst(offset), line: line)
  }

  private func name(of text: ArraySlice<UInt8>, line: Int) throws(PatchReadingError) -> String {
    guard text.first == Self.quote else { return Self.name(text) }
    guard let (bytes, _) = GitQuotedName.unquoted(text) else {
      throw .malformedFileName(line: line + 1)
    }
    return Self.name(bytes)
  }

  /// The names of the line `Binary files <old> and <new> differ`, or `nil` if `line` is not one;
  /// `nil` stands for `/dev/null`.
  private func binaryNames(_ line: Int) -> (old: String?, new: String?)? {
    let text = headerText(line)
    let (prefix, suffix) = (Array("Binary files ".utf8), Array(" differ".utf8))
    guard text.starts(with: prefix), text.count > prefix.count + suffix.count,
      text.suffix(suffix.count).elementsEqual(suffix)
    else { return nil }
    let names = text[prefix.count..<text.count - suffix.count]
    guard let and = names.firstRange(of: Array(" and ".utf8)) else { return nil }
    let (old, new) = (Self.name(names[..<and.lowerBound]), Self.name(names[and.upperBound...]))
    return (old == "/dev/null" ? nil : old, new == "/dev/null" ? nil : new)
  }

  /// The text of `line` without its line ending, for reading a header.
  private func headerText(_ line: Int) -> ArraySlice<UInt8> {
    var end = lineStarts[line + 1]
    if end > lineStarts[line], bytes[end - 1] == Self.lineFeed { end -= 1 }
    if end > lineStarts[line], bytes[end - 1] == Self.carriageReturn { end -= 1 }
    return Array(bytes[lineStarts[line]..<end])[...]
  }

  private func hasPrefix(_ line: Int, _ prefix: String) -> Bool {
    let start = lineStarts[line]
    let prefix = prefix.utf8
    guard lineStarts[line + 1] - start >= prefix.count else { return false }
    return bytes[start..<start + prefix.count].elementsEqual(prefix)
  }

  private func firstByte(_ line: Int) -> UInt8? {
    lineStarts[line] < lineStarts[line + 1] ? bytes[lineStarts[line]] : nil
  }

  /// Whether `line` holds nothing but its line ending.
  private func isBlank(_ line: Int) -> Bool {
    headerText(line).isEmpty
  }

  private static func name(_ bytes: some Sequence<UInt8>) -> String {
    String(decoding: Array(bytes), as: UTF8.self)
  }

  static let lineFeed = UInt8(ascii: "\n")
  private static let carriageReturn = UInt8(ascii: "\r")
  private static let space = UInt8(ascii: " ")
  private static let tab = UInt8(ascii: "\t")
  private static let minus = UInt8(ascii: "-")
  private static let plus = UInt8(ascii: "+")
  private static let backslash = UInt8(ascii: "\\")
  private static let quote = UInt8(ascii: "\"")
  private static let slash = UInt8(ascii: "/")
}

/// What the headers of one file say, until its hunks are read.
private struct FileHeader {
  /// The names of the line `diff --git`, prefixes included, if the file has one.
  var gitNames: (old: String, new: String)?

  /// The names of the lines `---` and `+++`, if the file has them; `nil` for `/dev/null`.
  var nameLines: (old: String?, new: String?)?

  var isAdded = false
  var isDeleted = false
  var isBinary = false
  var renamedFrom: String?
  var renamedTo: String?
  var hunks: [Patch.Hunk] = []

  init(gitNames: (old: String, new: String)) {
    self.gitNames = gitNames
  }

  init(nameLines: (old: String?, new: String?)) {
    self.nameLines = nameLines
  }

  init(binaryNames: (old: String?, new: String?)) {
    nameLines = binaryNames
    isBinary = true
  }

  /// Whether the lines `---` and `+++` that follow belong to this file: it has a line
  /// `diff --git` and neither these lines nor hunks yet.
  var takesNameLines: Bool {
    gitNames != nil && nameLines == nil && hunks.isEmpty
  }

  /// Whether the lines that follow may be the extended headers of Git.
  var takesExtendedHeaders: Bool {
    takesNameLines && !isBinary
  }

  /// The file, or `nil` if the patch says nothing about its lines or names: only its mode
  /// changes, or it has names but no hunks.
  var file: Patch.File? {
    var (old, new): (String?, String?)
    if let nameLines {
      (old, new) = nameLines
    } else if let gitNames {
      (old, new) = (isAdded ? nil : gitNames.old, isDeleted ? nil : gitNames.new)
    } else {
      return nil
    }
    if gitNames != nil {
      // Git writes a prefix of one letter before every path, `a/` and `b/` or, with
      // `diff.mnemonicPrefix`, one that names the side, such as `i/` and `w/`.
      old = old.map(Self.withoutPrefix)
      new = new.map(Self.withoutPrefix)
    } else if old?.hasPrefix("a/") ?? true, new?.hasPrefix("b/") ?? true {
      old = old.map { String($0.dropFirst(2)) }
      new = new.map { String($0.dropFirst(2)) }
    }
    old = renamedFrom ?? old
    new = renamedTo ?? new
    let saysSomething =
      !hunks.isEmpty || isBinary || isAdded || isDeleted || old != new
      || (gitNames == nil && (old == nil || new == nil))
    guard saysSomething else { return nil }
    return Patch.File(oldPath: old, newPath: new, isBinary: isBinary, hunks: hunks)
  }

  /// The letters of the prefixes that Git writes before the paths of a file: `a` and `b`, and
  /// those of `diff.mnemonicPrefix` for commit, index, work tree, object and the two sides of
  /// `--no-index`.
  static let prefixLetters: Set<UInt8> = Set("abciwo12".utf8)

  /// `path` without a prefix of Git, such as `a/`, if it starts with one.
  private static func withoutPrefix(_ path: String) -> String {
    let bytes = path.utf8
    guard bytes.count > 2, let first = bytes.first, prefixLetters.contains(first),
      bytes.dropFirst().first == UInt8(ascii: "/")
    else { return path }
    return String(path.dropFirst(2))
  }
}

/// Reads the numbers of the header of a hunk.
private struct HeaderScanner {
  var text: ArraySlice<UInt8>

  /// Skips `byte` if it comes next, and tells whether it did.
  mutating func skip(_ byte: UInt8) -> Bool {
    guard text.first == byte else { return false }
    text = text.dropFirst()
    return true
  }

  /// Reads `start[,count]`; the count is 1 where it is left out.
  mutating func range() -> Patch.LineRange? {
    guard let start = number() else { return nil }
    let count = skip(UInt8(ascii: ",")) ? number() : 1
    guard let count, start > 0 || count == 0 else { return nil }
    return Patch.LineRange(start: start, count: count)
  }

  /// Reads a number of at most nine digits, so that every line number fits into 32 bits.
  private mutating func number() -> Int? {
    let digits = text.prefix { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
    guard (1...9).contains(digits.count) else { return nil }
    text = text.dropFirst(digits.count)
    return digits.reduce(0) { $0 * 10 + Int($1 - UInt8(ascii: "0")) }
  }
}

extension Patch.Line {
  /// Takes the line feed off the end of the line, as the line `\ No newline at end of file` that
  /// follows it says; a line without one stays as it is.
  fileprivate mutating func dropLineFeed(in bytes: Data) {
    if !self.bytes.isEmpty, bytes[self.bytes.upperBound - 1] == UInt8(ascii: "\n") {
      self.bytes = self.bytes.lowerBound..<self.bytes.upperBound - 1
    }
  }
}
