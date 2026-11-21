import Foundation
import MergeModel
import Testing
import TextBasics

/// Random sequences of copies in both directions and returns to the comparison before a copy,
/// with files in UTF-8, in UTF-16 with a byte order mark and in Windows-1252.
struct ChangeCopyFuzzTests {
  /// One step of a sequence.
  enum Action: CustomStringConvertible {
    case copy(block: Int, from: Role)
    case copyAll(from: Role)
    case undo

    var description: String {
      switch self {
      case .copy(let block, let source): "copy block \(block) from \(source)"
      case .copyAll(let source): "copy all changes from \(source)"
      case .undo: "undo"
      }
    }
  }

  /// How often the sequences met the cases that only some inputs have.
  struct Coverage: CustomStringConvertible {
    var copiesToUTF16 = 0
    var copiesToWindows1252 = 0
    var unrepresentableCopies = 0
    var copiesBack = 0

    var description: String {
      "UTF-16 \(copiesToUTF16), Windows-1252 \(copiesToWindows1252), "
        + "unrepresentable \(unrepresentableCopies), copied back \(copiesBack)"
    }
  }

  @Test func randomCopiesKeepTheUntouchedBytesAndCopyTheTextOfTheSource() async throws {
    let seed: UInt64 = 2036
    var generator = SplitMix64(seed: seed)
    var coverage = Coverage()
    for sequence in 0..<2_000 {
      let input = RandomComparisonInput(using: &generator)
      // Each comparison with the side the copy that made it wrote to.
      var history: [(session: Session, target: Role)] = [(try await input.session(), .a)]
      var actions: [Action] = []
      for _ in 0..<Int.random(in: 1...8, using: &generator) {
        let session = history[history.count - 1].session
        let changed = session.blocks.filter { $0.kind == .changed }
        let source: Role = Bool.random(using: &generator) ? .a : .b
        let action: Action =
          switch Int.random(in: 0..<10, using: &generator) {
          case 0..<2 where history.count > 1: .undo
          case 2 where !changed.isEmpty: .copyAll(from: source)
          default:
            changed.randomElement(using: &generator).map { .copy(block: $0.id, from: source) }
              ?? (history.count > 1 ? .undo : .copyAll(from: source))
          }
        actions.append(action)
        let context = Comment(
          rawValue: "seed \(seed), sequence \(sequence), \(input), actions \(actions)")
        let copy: ChangeCopy
        switch action {
        case .undo:
          let last = history.removeLast()
          try await Self.checkCopyingBack(
            to: history[history.count - 1].session, from: last.session, in: last.target,
            &coverage, context)
          continue
        case .copy(let block, let source):
          copy = ChangeCopy(block: session.blocks[block], from: source)
        case .copyAll(let source):
          copy = ChangeCopy(allChangesFrom: source)
        }
        let target = try #require(session.inputs[copy.target])
        if let encoding = Self.encodingLacking(copy, in: session) {
          await #expect(throws: MergeModelError.unrepresentableText(encoding), context) {
            try await session.copying(copy)
          }
          coverage.unrepresentableCopies += 1
          continue
        }
        let copied = try await session.copying(copy)
        switch action {
        case .copy(let block, let source):
          try Self.checkCopy(
            of: session.blocks[block], from: source, in: session, to: copied, context)
        default:
          try Self.checkCopyAll(from: copy.source, in: session, to: copied, context)
        }
        try Self.checkEncoding(of: copied.inputs[copy.target], like: target, context)
        if target.encoding == .utf16LittleEndian { coverage.copiesToUTF16 += 1 }
        if target.encoding == .windows1252 { coverage.copiesToWindows1252 += 1 }
        history.append((copied, copy.target))
      }
    }
    let summary = Comment(rawValue: "seed \(seed), \(coverage)")
    #expect(coverage.copiesToUTF16 > 100, summary)
    #expect(coverage.copiesToWindows1252 > 100, summary)
    #expect(coverage.unrepresentableCopies > 10, summary)
    #expect(coverage.copiesBack > 100, summary)
  }

  /// The encoding of the target of `copy` if it cannot represent the text that the copy takes
  /// from the source, else `nil`.
  static func encodingLacking(_ copy: ChangeCopy, in session: Session) -> FileEncoding? {
    guard let source = session.inputs[copy.source], let target = session.inputs[copy.target],
      let encoding = target.encoding
    else { return nil }
    let blocks: [Block]
    switch copy.extent {
    case .block(let id): blocks = [session.blocks[id]]
    case .allChanges: blocks = session.blocks.filter { $0.kind == .changed }
    }
    let text = utf8(of: source)
    let lines = lineStarts(of: text, in: session.options.mode)
    let copied = blocks.map { block in
      String(
        decoding: text[
          lines[
            block.lines(in: copy.source).lowerBound]..<lines[
              block.lines(in: copy.source).upperBound]], as: UTF8.self)
    }.joined()
    return copied.data(using: encoding.foundationEncoding, allowLossyConversion: false) == nil
      ? encoding : nil
  }

  /// Checks that `copied`, the target after a copy, keeps the encoding and byte order mark of
  /// `target` and holds exactly the bytes of its text in that form.
  static func checkEncoding(
    of copied: SourceFile?, like target: SourceFile, _ context: Comment
  ) throws {
    let copied = try #require(copied, context)
    let encoding = try #require(target.encoding, context)
    #expect(copied.encoding == encoding, context)
    #expect(copied.hasByteOrderMark == target.hasByteOrderMark, context)
    let text = try #require(copied.text, context)
    let encoded = try #require(text.data(using: encoding.foundationEncoding), context)
    let byteOrderMark = target.hasByteOrderMark ? encoding.byteOrderMark : []
    #expect(copied.bytes == Data(byteOrderMark) + encoded, context)
  }

  /// Checks a return to `previous` from `current`, which a copy to the file of `target` made, by
  /// copying the text before back: in a comparison of the file before with the file after, in
  /// exact mode, copying every change from the file before gives back its bytes.
  ///
  /// Copied lines take the predominant line ending, so this holds where the file before ends
  /// its lines alike, or has no line break.
  static func checkCopyingBack(
    to previous: Session, from current: Session, in target: Role, _ coverage: inout Coverage,
    _ context: Comment
  ) async throws {
    let before = try #require(previous.inputs[target], context)
    let after = try #require(current.inputs[target], context)
    guard before.lineEndingStyle?.uniformLineEnding != nil || before.lineEndingStyle == nil
    else { return }
    let back = try await Session.diff(old: before, new: after, mode: .exact)

    let restored = try back.file(after: ChangeCopy(allChangesFrom: .a))

    #expect(restored.bytes == before.bytes, context)
    coverage.copiesBack += 1
  }

  /// Checks a copy of `block` from `source` in `session`, which gave `copied`, on the UTF-8 of
  /// the texts.
  static func checkCopy(
    of block: Block, from source: Role, in session: Session, to copied: Session,
    _ context: Comment
  ) throws {
    let target: Role = source == .a ? .b : .a
    let mode = session.options.mode
    let sourceBytes = try utf8(of: #require(session.inputs[source], context))
    let targetBytes = try utf8(of: #require(session.inputs[target], context))
    let result = try utf8(of: #require(copied.inputs[target], context))
    let sourceLines = Self.lineStarts(of: sourceBytes, in: mode)
    let targetLines = Self.lineStarts(of: targetBytes, in: mode)
    try #require(sourceLines.count - 1 == session.rowLayout.lineCount(in: source), context)
    try #require(targetLines.count - 1 == session.rowLayout.lineCount(in: target), context)
    try checkCovering(copied, context)
    #expect(copied.inputs[source]?.bytes == session.inputs[source]?.bytes, context)

    let replaced =
      targetLines[
        block.lines(in: target).lowerBound]..<targetLines[
        block.lines(in: target).upperBound]
    let suffixLength = targetBytes.count - replaced.upperBound
    try #require(result.count >= replaced.lowerBound + suffixLength, context)
    #expect(result.prefix(replaced.lowerBound) == targetBytes.prefix(replaced.lowerBound), context)
    #expect(result.suffix(suffixLength) == targetBytes.suffix(suffixLength), context)

    let lines = block.lines(in: source)
    let copiedText = Array(
      sourceBytes[sourceLines[lines.lowerBound]..<sourceLines[lines.upperBound]])
    var middle = Array(result[replaced.lowerBound..<(result.count - suffixLength)])
    // A last line of the target without a line ending ends before lines are added after it.
    if !lines.isEmpty, replaced.lowerBound > 0, !isLineEnding(targetBytes[replaced.lowerBound - 1])
    {
      let ending = lineEnding(at: 0, in: middle)
      #expect(ending > 0, context)
      middle.removeFirst(ending)
    }
    #expect(contents(of: middle) == contents(of: copiedText), context)
    if let lineEnding = session.inputs[target]?.predominantLineEnding {
      #expect(endings(of: middle).allSatisfy { $0 == lineEnding.bytes }, context)
    }
    if !lines.isEmpty, lines.upperBound == sourceLines.count - 1, suffixLength == 0 {
      #expect(
        result.last.map(isLineEnding) == sourceBytes.last.map(isLineEnding), context)
    }
  }

  /// Checks a copy of every changed block from `source` in `session`, which gave `copied`.
  static func checkCopyAll(
    from source: Role, in session: Session, to copied: Session, _ context: Comment
  ) throws {
    let target: Role = source == .a ? .b : .a
    try checkCovering(copied, context)
    #expect(copied.inputs[source]?.bytes == session.inputs[source]?.bytes, context)
    let sourceFile = session.inputs[source]
    let targetStyle = session.inputs[target]?.lineEndingStyle
    // The exact mode tells line endings apart, except that it reads a file whose line breaks
    // are all CR as if they were LF; only alike line endings come out equal.
    let keepsLineEndings =
      sourceFile?.lineEndingStyle == nil || targetStyle == nil
      || (sourceFile?.lineEndingStyle == targetStyle && targetStyle?.uniformLineEnding != nil)
    guard session.options.mode != .exact || keepsLineEndings else { return }
    #expect(!copied.blocks.contains { $0.kind == .changed }, context)
    if session.options.mode == .exact, session.ignoreRules.isEmpty {
      #expect(copied.inputs[target]?.text == sourceFile?.text, context)
    }
  }

  /// The UTF-8 of the text of `file`.
  static func utf8(of file: SourceFile) -> [UInt8] {
    Array((file.text ?? "").utf8)
  }

  /// Checks that the blocks of `session` cover the lines of both files in order.
  static func checkCovering(_ session: Session, _ context: Comment) throws {
    for role in [Role.a, .b] {
      var next = 0
      for block in session.blocks {
        #expect(block.lines(in: role).lowerBound == next, context)
        next = block.lines(in: role).upperBound
      }
      #expect(next == session.rowLayout.lineCount(in: role), context)
    }
  }

  /// The offsets where the lines of `bytes` start as a comparison in `mode` splits them, and the
  /// byte count.
  ///
  /// Every mode ends a line after LF, and every mode other than exact also after a CR that no LF
  /// follows; so does the exact mode in a text whose line breaks are all CR.
  static func lineStarts(of bytes: [UInt8], in mode: ComparisonMode) -> [Int] {
    let carriageReturn = UInt8(ascii: "\r")
    let lineFeed = UInt8(ascii: "\n")
    let onlyCR = bytes.contains(carriageReturn) && !bytes.contains(lineFeed)
    var starts = [0]
    for (index, byte) in bytes.enumerated() {
      let next = index + 1 < bytes.count ? bytes[index + 1] : nil
      let endsLine =
        byte == lineFeed
        || (byte == carriageReturn && next != lineFeed && (mode != .exact || onlyCR))
      if endsLine, index + 1 < bytes.count { starts.append(index + 1) }
    }
    if !bytes.isEmpty { starts.append(bytes.count) }
    return starts
  }

  /// The contents of the lines of `bytes`, split at every line ending; a final line ending ends
  /// the last line.
  static func contents(of bytes: [UInt8]) -> [[UInt8]] {
    var lines: [[UInt8]] = []
    var current: [UInt8] = []
    var index = 0
    while index < bytes.count {
      let ending = lineEnding(at: index, in: bytes)
      if ending > 0 {
        lines.append(current)
        current = []
        index += ending
      } else {
        current.append(bytes[index])
        index += 1
      }
    }
    if !current.isEmpty { lines.append(current) }
    return lines
  }

  /// The line endings of `bytes`, in order.
  static func endings(of bytes: [UInt8]) -> [[UInt8]] {
    var endings: [[UInt8]] = []
    var index = 0
    while index < bytes.count {
      let ending = lineEnding(at: index, in: bytes)
      if ending > 0 {
        endings.append(Array(bytes[index..<(index + ending)]))
        index += ending
      } else {
        index += 1
      }
    }
    return endings
  }

  /// The length of the line ending CRLF, CR or LF at `index`, or 0.
  static func lineEnding(at index: Int, in bytes: [UInt8]) -> Int {
    guard index < bytes.count, isLineEnding(bytes[index]) else { return 0 }
    let isPair =
      bytes[index] == UInt8(ascii: "\r") && index + 1 < bytes.count
      && bytes[index + 1] == UInt8(ascii: "\n")
    return isPair ? 2 : 1
  }

  static func isLineEnding(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
  }
}

extension FileEncoding {
  /// The same encoding in Foundation, which the tests use as an independent encoder.
  var foundationEncoding: String.Encoding {
    switch self {
    case .utf8: .utf8
    case .utf16LittleEndian: .utf16LittleEndian
    case .utf16BigEndian: .utf16BigEndian
    case .utf32LittleEndian: .utf32LittleEndian
    case .utf32BigEndian: .utf32BigEndian
    case .windows1252: .windowsCP1252
    case .isoLatin1: .isoLatin1
    case .macRoman: .macOSRoman
    }
  }

  /// The byte order mark, spelled out independently of the implementation.
  var byteOrderMark: [UInt8] {
    switch self {
    case .utf8: [0xEF, 0xBB, 0xBF]
    case .utf16LittleEndian: [0xFF, 0xFE]
    case .utf16BigEndian: [0xFE, 0xFF]
    case .utf32LittleEndian: [0xFF, 0xFE, 0x00, 0x00]
    case .utf32BigEndian: [0x00, 0x00, 0xFE, 0xFF]
    case .windows1252, .isoLatin1, .macRoman: []
    }
  }
}

extension LineEnding {
  /// The bytes of the line ending, spelled out independently of the implementation.
  fileprivate var bytes: [UInt8] {
    switch self {
    case .lf: [UInt8(ascii: "\n")]
    case .crlf: [UInt8(ascii: "\r"), UInt8(ascii: "\n")]
    case .cr: [UInt8(ascii: "\r")]
    }
  }
}

/// Two files of a comparison built from a small vocabulary, so that equal lines, whitespace
/// changes, lines an ignore rule matches, every kind of line ending and missing final line
/// breaks are frequent.
struct RandomComparisonInput: CustomStringConvertible {
  let old: String
  let new: String
  let oldEncoding: FileEncoding
  let newEncoding: FileEncoding
  let mode: ComparisonMode
  let rules: [IgnoreRule]

  /// A line that only Windows-1252 has the bytes for, so that a file with it is recognized as
  /// Windows-1252.
  static let windowsLine = "\u{201C}w\u{201D}"

  init(using generator: inout SplitMix64) {
    let vocabulary = [
      "l0", "l1", "l2", "\u{E4}3", " l4", "l4", "l5  ", "x # 7", "x # 8", "\u{2713}9", "",
    ]
    let lines = (0..<Int.random(in: 0...8, using: &generator)).map { _ in
      vocabulary.randomElement(using: &generator) ?? ""
    }
    oldEncoding = Self.encoding(using: &generator)
    newEncoding = Self.encoding(using: &generator)
    old = Self.text(
      of: Self.edit(lines, using: &generator), in: oldEncoding, using: &generator)
    new = Self.text(
      of: Self.edit(lines, using: &generator), in: newEncoding, using: &generator)
    mode = ComparisonMode.allCases.randomElement(using: &generator) ?? .exact
    rules =
      Int.random(in: 0..<5, using: &generator) == 0
      ? [IgnoreRule(name: "Number", pattern: #"# \d"#)] : []
  }

  var description: String {
    "old: \(old.debugDescription) in \(oldEncoding) new: \(new.debugDescription) in "
      + "\(newEncoding) mode: \(mode) rules: \(rules.count)"
  }

  func session() async throws -> Session {
    try await Session.diff(
      old: SourceFile(bytes: Self.bytes(of: old, in: oldEncoding), label: "old"),
      new: SourceFile(bytes: Self.bytes(of: new, in: newEncoding), label: "new"), mode: mode,
      ignoring: rules)
  }

  /// UTF-8 mostly, else UTF-16 with a byte order mark or Windows-1252.
  private static func encoding(using generator: inout SplitMix64) -> FileEncoding {
    switch Int.random(in: 0..<5, using: &generator) {
    case 0: .utf16LittleEndian
    case 1: .windows1252
    default: .utf8
    }
  }

  /// The bytes of a file holding `text` in `encoding`, with a byte order mark in UTF-16.
  private static func bytes(of text: String, in encoding: FileEncoding) -> Data {
    let bytes = text.data(using: encoding.foundationEncoding) ?? Data()
    return encoding == .utf16LittleEndian ? Data(encoding.byteOrderMark) + bytes : bytes
  }

  /// Up to four edits: delete, replace, indent or insert a line.
  private static func edit(_ lines: [String], using generator: inout SplitMix64) -> [String] {
    var edited = lines
    for _ in 0..<Int.random(in: 0...4, using: &generator) {
      let position = Int.random(in: 0...edited.count, using: &generator)
      let inRange = position < edited.count
      switch Int.random(in: 0...4, using: &generator) {
      case 0 where inRange:
        edited.remove(at: position)
      case 1 where inRange:
        edited[position] = "y\(Int.random(in: 0...2, using: &generator))"
      case 2 where inRange:
        edited[position] = "  " + edited[position] + "\t"
      default:
        edited.insert("n\(Int.random(in: 0...2, using: &generator))", at: position)
      }
    }
    return edited
  }

  /// The lines joined with LF mostly, else with CRLF, with CR or with a mix of the three, and
  /// without a final line ending now and then.
  ///
  /// A file in Windows-1252 starts with ``windowsLine`` and has no character the encoding lacks.
  private static func text(
    of lines: [String], in encoding: FileEncoding, using generator: inout SplitMix64
  ) -> String {
    let endings = ["\n", "\r\n", "\r"]
    let style = Int.random(in: 0..<10, using: &generator)
    let lines =
      encoding == .windows1252
      ? [windowsLine] + lines.map { $0.replacing("\u{2713}", with: "v") } : lines
    var text = lines.map { line in
      let ending =
        switch style {
        case 0..<6: "\n"
        case 6: "\r\n"
        case 7: "\r"
        default: endings.randomElement(using: &generator) ?? "\n"
        }
      return line + ending
    }.joined()
    if Int.random(in: 0..<3, using: &generator) == 0, !text.isEmpty {
      text.unicodeScalars.removeLast()
      if text.unicodeScalars.last == "\r" { text.unicodeScalars.removeLast() }
    }
    return text
  }
}
