import Foundation
import TextBasics
import TextIO

extension Session {
  /// The file of the target of `copy` after the copy.
  ///
  /// The lines of each block that the copy takes, as the comparison mode splits them, give way to
  /// the lines of the source as its file holds them: its own text, never the text the comparison
  /// saw without whitespace or without what the ignore rules match. Every line break of the
  /// copied lines becomes the predominant line ending of the target, a lone CR within a line of
  /// the exact mode too; where the target has no line break, the copied lines keep their own.
  /// Where the copy ends with the last line of the source and no text of the target follows, the
  /// target ends with a line break exactly when the source does. Every other byte of the target
  /// stays as it is, and the file keeps the location, label, encoding and byte order mark of the
  /// target.
  ///
  /// The comparison of the files does not change; ``copying(_:)`` compares them anew.
  ///
  /// - Precondition: The session is a comparison, and a copy of one block names a changed block.
  /// - Throws: ``MergeModelError/unrepresentableText(_:)`` if the encoding of the target cannot
  ///   represent a character of the copied text.
  public func file(after copy: ChangeCopy) throws(MergeModelError) -> SourceFile {
    precondition(kind == .diff, "Only a comparison copies text between its files")
    guard let source = files[copy.source], let target = files[copy.target] else {
      preconditionFailure("A comparison has the files A and B")
    }
    let copiedBlocks: [Block]
    switch copy.extent {
    case .block(let id):
      precondition(
        blocks.indices.contains(id) && blocks[id].kind == .changed,
        "Block \(id) is not a changed block of the comparison")
      copiedBlocks = [blocks[id]]
    case .allChanges:
      copiedBlocks = blocks.filter { $0.kind == .changed }
    }
    var text = CopiedText(source: source, target: target)
    for block in copiedBlocks {
      text.copy(lines: block.lines(in: copy.source), over: block.lines(in: copy.target))
    }
    guard let encoding = target.file.encoding else {
      preconditionFailure("A session never compares a binary file")
    }
    let bytes: Data
    do {
      bytes = try encoding.textEncoding.encode(
        utf8: text.finished(), withByteOrderMark: target.file.hasByteOrderMark)
    } catch {
      throw .unrepresentableText(encoding)
    }
    return SourceFile(
      bytes: bytes, label: target.file.label, url: target.file.url, encoding: encoding)
  }

  /// The comparison after `copy`: the files with the target as ``file(after:)`` gives it,
  /// compared anew in the same comparison mode and with the same ignore rules.
  ///
  /// Nothing of the session changes, so keeping it is enough to undo the copy. The copy and the
  /// comparison run off the calling actor.
  ///
  /// - Precondition: The session is a comparison, and a copy of one block names a changed block.
  /// - Throws: ``MergeModelError/unrepresentableText(_:)`` if the encoding of the target cannot
  ///   represent a character of the copied text, or the error of the comparison.
  @concurrent
  public func copying(_ copy: ChangeCopy) async throws(MergeModelError) -> Session {
    let copied = try file(after: copy)
    let inputs = inputs
    return try await Session.diff(
      old: copy.target == .a ? copied : inputs.a, new: copy.target == .b ? copied : inputs.b,
      mode: options.mode, ignoring: ignoreRules)
  }
}

/// The UTF-8 text of the target of a copy, put together in order from the bytes of the target
/// it keeps and the lines of the source it copies.
private struct CopiedText {
  /// The file whose lines are copied.
  private let source: ComparedFile

  /// The file whose lines are replaced.
  private let target: ComparedFile

  /// The UTF-8 text of the source as its file holds it.
  private let sourceText: Data

  /// The UTF-8 text of the target as its file holds it.
  private let targetText: Data

  /// The line ending of every copied line that has one, or `nil` to keep the line's own.
  private let lineEnding: [UInt8]?

  /// The line ending that ends a line without one when text comes after it.
  private let addedLineEnding: [UInt8]

  private var text: [UInt8] = []

  /// The offset in ``targetText`` up to which the target is taken over.
  private var position = 0

  /// Whether ``text`` ends in a line that has no line ending.
  private var endsWithinLine = false

  init(source: ComparedFile, target: ComparedFile) {
    guard let sourceText = source.file.utf8, let targetText = target.file.utf8 else {
      preconditionFailure("A session never compares a binary file")
    }
    self.source = source
    self.target = target
    self.sourceText = sourceText
    self.targetText = targetText
    let ownLineEnding = target.file.predominantLineEnding
    lineEnding = ownLineEnding.map { Self.utf8(of: $0) }
    addedLineEnding = Self.utf8(
      of: ownLineEnding ?? source.file.predominantLineEnding ?? .lf)
    text.reserveCapacity(targetText.count)
  }

  /// Replaces the lines `replaced` of the target with the lines `lines` of the source.
  ///
  /// - Precondition: `replaced` starts no earlier than the lines that the previous call replaced
  ///   end.
  mutating func copy(lines: Range<Int>, over replaced: Range<Int>) {
    let replacedBytes = target.byteRange(ofLines: replaced)
    precondition(replacedBytes.lowerBound >= position, "Blocks are copied in their order")
    keep(position..<replacedBytes.lowerBound)
    for line in lines {
      append(line)
    }
    position = replacedBytes.upperBound
  }

  /// The text, with the rest of the target after the last copied lines.
  mutating func finished() -> [UInt8] {
    keep(position..<targetText.count)
    return text
  }

  private mutating func keep(_ bytes: Range<Int>) {
    guard !bytes.isEmpty else { return }
    endLine()
    text.append(contentsOf: targetText[bytes])
    endsWithinLine = !Self.isLineEnding(targetText[bytes.upperBound - 1])
  }

  private mutating func append(_ line: Int) {
    endLine()
    let bytes = source.byteRange(ofLines: line..<(line + 1))
    endsWithinLine = !Self.isLineEnding(sourceText[bytes.upperBound - 1])
    guard let lineEnding else {
      text.append(contentsOf: sourceText[bytes])
      return
    }
    // A line of the exact mode may hold a lone CR, which is a line break of the file all the
    // same. It takes the line ending of the target like every other one, so that no CR of the
    // source comes to stand before an LF of the target and joins it.
    var start = bytes.lowerBound
    var index = start
    while index < bytes.upperBound {
      let byte = sourceText[index]
      guard Self.isLineEnding(byte) else {
        index += 1
        continue
      }
      text.append(contentsOf: sourceText[start..<index])
      text.append(contentsOf: lineEnding)
      let isPair =
        byte == UInt8(ascii: "\r") && index + 1 < bytes.upperBound
        && sourceText[index + 1] == UInt8(ascii: "\n")
      index += isPair ? 2 : 1
      start = index
    }
    text.append(contentsOf: sourceText[start..<bytes.upperBound])
  }

  /// Ends the last line of ``text`` if it has no line ending, before text comes after it.
  private mutating func endLine() {
    if endsWithinLine {
      text.append(contentsOf: addedLineEnding)
      endsWithinLine = false
    }
  }

  private static func isLineEnding(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
  }

  private static func utf8(of lineEnding: LineEnding) -> [UInt8] {
    switch lineEnding {
    case .lf: [UInt8(ascii: "\n")]
    case .crlf: [UInt8(ascii: "\r"), UInt8(ascii: "\n")]
    case .cr: [UInt8(ascii: "\r")]
    }
  }
}
