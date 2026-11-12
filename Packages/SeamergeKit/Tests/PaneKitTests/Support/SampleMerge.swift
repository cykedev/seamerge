import Foundation
import PaneKit

/// A three-way merge of a real source file with one block of every kind, laid out on one grid
/// the way the merge model lays it out.
///
/// The base is the start of `Transcoder.swift` from TextIO; both sides change it the way people
/// do, so that the pictures show real code rather than placeholder text.
struct SampleMerge {
  /// The side of a merge that a pane shows.
  enum Side: CaseIterable {
    case a
    case base
    case b
  }

  /// How a conflict stands in the result.
  enum Resolution {
    case open
    case handwritten([String])
  }

  /// A run of lines that is the same on every side, or a block that changes them.
  enum Chunk {
    case same([String])
    case onlyA(a: [String], base: [String], marker: Marker)
    case onlyB(base: [String], b: [String], marker: Marker)
    case both(a: [String], base: [String], b: [String], marker: Marker)
    case conflict(
      a: [String], base: [String], b: [String], markers: (a: Marker, b: Marker),
      resolution: Resolution)
  }

  let chunks: [Chunk]

  /// The base rows whose B line differs only in what the comparison ignores.
  let ignoredDifferenceRowsOfB: IndexSet

  /// The sample merge used throughout the tests and pictures.
  static let transcoder = SampleMerge(
    chunks: [
      .same(["import Foundation", ""]),
      .onlyA(
        a: [
          "/// Converts between bytes in a ``TextEncoding`` and strings without losing anything."
        ],
        base: [
          "/// Converts between bytes in a ``TextEncoding`` and Swift strings without losing anything."
        ],
        marker: .changed),
      .same([
        "///",
        "/// Every conversion is strict: a byte sequence that is not valid in the encoding, or a character",
        "/// the encoding cannot represent, makes the conversion fail instead of being replaced.",
        "enum Transcoder {",
      ]),
      .onlyB(
        base: [],
        b: [
          "  /// The encodings that every conversion supports.",
          "  static let supportedEncodings = TextEncoding.allCases",
        ],
        marker: .added),
      .same([
        "  /// Decodes `bytes`, which hold no byte order mark, or returns `nil` if they are not valid in",
        "  /// `encoding`.",
        "  ///",
      ]),
      .conflict(
        a: [
          "  /// A single-byte encoding succeeds only if encoding the text again gives back the same bytes, so"
        ],
        base: [
          "  /// A single-byte encoding only succeeds if encoding the text again gives back the same bytes, so"
        ],
        b: [
          "  /// A single-byte encoding only succeeds if encoding the text again returns the same bytes, so"
        ],
        markers: (a: .changed, b: .changed),
        resolution: .handwritten([
          "  /// A single-byte encoding succeeds only if encoding the text again returns the same bytes, so"
        ])),
      .same([
        "  /// that writing an unchanged file reproduces it exactly.",
        "  static func decode(_ bytes: Data, from encoding: TextEncoding) -> String? {",
        "    switch encoding {",
        "    case .utf8:",
      ]),
      .both(
        a: ["      return String(validating: bytes, as: Unicode.UTF8.self)"],
        base: ["      return String(validating: bytes, as: UTF8.self)"],
        b: ["      return String(validating: bytes, as: Unicode.UTF8.self)"],
        marker: .changed),
      .same([
        "    case .utf16LittleEndian:",
        "      return decode(bytes, as: UTF16.self, bigEndian: false)",
        "    case .utf16BigEndian:",
        "      return decode(bytes, as: UTF16.self, bigEndian: true)",
        "    case .utf32LittleEndian:",
        "      return decode(bytes, as: UTF32.self, bigEndian: false)",
      ]),
      .onlyA(
        a: [],
        base: [
          "    case .utf32BigEndian:",
          "      return decode(bytes, as: UTF32.self, bigEndian: true)",
        ],
        marker: .removed),
      .same(["    case .windows1252, .isoLatin1, .macRoman:"]),
      .conflict(
        a: [
          "      guard let legacyEncoding = encoding.singleByteFoundationEncoding,",
          "        let text = String(data: bytes, encoding: legacyEncoding),",
          "        text.data(using: legacyEncoding) == bytes",
        ],
        base: [
          "      guard let foundationEncoding = encoding.singleByteFoundationEncoding,",
          "        let text = String(data: bytes, encoding: foundationEncoding),",
          "        text.data(using: foundationEncoding, allowLossyConversion: false) == bytes",
        ],
        b: [
          "      guard let foundationEncoding = encoding.singleByteFoundationEncoding,",
          "        let text = String(bytes, encoding: foundationEncoding),",
          "        text.data(using: foundationEncoding, allowLossyConversion: false) == bytes,",
          "        !text.isEmpty",
        ],
        markers: (a: .changed, b: .changed),
        resolution: .open),
      .same([
        "      else { return nil }",
        "      return text",
        "    }",
        "  }",
      ]),
    ],
    ignoredDifferenceRowsOfB: [15])

  /// The index of the open conflict among the blocks, the block the pictures show as current.
  static let openConflictBlock = 5

  /// The content of the pane of `side` on the grid of the upper panes.
  ///
  /// With `baseHidden`, the warning sign of a conflict moves from the base pane to B.
  func content(of side: Side, baseHidden: Bool = false) -> PaneContent {
    var builder = Builder()
    for chunk in chunks {
      switch chunk {
      case .same(let lines):
        builder.appendUnchanged(lines)
      case .onlyA(let a, let base, let marker):
        builder.append(
          lines(of: side, a: a, base: base, b: base), rowCount: max(a.count, base.count),
          style: style(of: side, changedBy: [.a], conflict: nil),
          marker: side == .a ? marker : nil)
      case .onlyB(let base, let b, let marker):
        builder.append(
          lines(of: side, a: base, base: base, b: b), rowCount: max(b.count, base.count),
          style: style(of: side, changedBy: [.b], conflict: nil),
          marker: side == .b ? marker : nil)
      case .both(let a, let base, let b, let marker):
        builder.append(
          lines(of: side, a: a, base: base, b: b), rowCount: max(a.count, base.count, b.count),
          style: style(of: side, changedBy: [.a, .b], conflict: nil),
          marker: side == .base ? nil : marker)
      case .conflict(let a, let base, let b, let markers, let resolution):
        let conflict: ConflictMarker
        if case .open = resolution { conflict = .open } else { conflict = .resolved }
        let carriesWarning = side == (baseHidden ? .b : .base)
        builder.append(
          lines(of: side, a: a, base: base, b: b), rowCount: max(a.count, base.count, b.count),
          style: style(of: side, changedBy: [.a, .b], conflict: conflict),
          marker: side == .a ? markers.a : side == .b ? markers.b : nil,
          conflict: carriesWarning ? conflict : nil)
      }
    }
    var content = builder.content
    if side == .b {
      content.ignoredDifferenceRows = ignoredDifferenceRowsOfB
    }
    return content
  }

  /// The two sides of a comparison of the base with B, each on the grid of the comparison.
  func diffContents() -> (left: PaneContent, right: PaneContent) {
    var left = Builder()
    var right = Builder()
    func change(_ old: [String], _ new: [String], marker: Marker) {
      let rowCount = max(old.count, new.count)
      left.append(old, rowCount: rowCount, style: .tinted(.a))
      right.append(new, rowCount: rowCount, style: .tinted(.b), marker: marker)
    }
    for chunk in chunks {
      switch chunk {
      case .same(let lines):
        left.appendUnchanged(lines)
        right.appendUnchanged(lines)
      case .onlyA(_, let base, _):
        left.appendUnchanged(base)
        right.appendUnchanged(base)
      case .onlyB(let base, let b, let marker):
        change(base, b, marker: marker)
      case .both(_, let base, let b, let marker):
        change(base, b, marker: marker)
      case .conflict(_, let base, let b, let markers, _):
        change(base, b, marker: markers.b)
      }
    }
    return (left.content, right.content)
  }

  /// The content of the result pane, which has a grid of its own: a block that only removes
  /// lines takes no rows there, and an open conflict shows the base text until it is decided.
  func resultContent() -> PaneContent {
    var builder = Builder()
    for chunk in chunks {
      switch chunk {
      case .same(let lines):
        builder.appendUnchanged(lines)
      case .onlyA(let a, _, _):
        builder.append(a, rowCount: a.count, style: .tinted(.a))
      case .onlyB(_, let b, _):
        builder.append(b, rowCount: b.count, style: .tinted(.b))
      case .both(let a, _, _, _):
        builder.append(a, rowCount: a.count, style: .combined)
      case .conflict(_, let base, _, _, .open):
        builder.append(base, rowCount: base.count, style: .unchanged)
      case .conflict(_, _, _, _, .handwritten(let lines)):
        builder.append(lines, rowCount: lines.count, style: .handwritten)
      }
    }
    return builder.content
  }

  private func lines(of side: Side, a: [String], base: [String], b: [String]) -> [String] {
    switch side {
    case .a: a
    case .base: base
    case .b: b
    }
  }

  private func style(
    of side: Side, changedBy changers: Set<Side>, conflict: ConflictMarker?
  ) -> BlockStyle {
    switch side {
    case .a: changers.contains(.a) ? .tinted(.a) : .unchanged
    case .b: changers.contains(.b) ? .tinted(.b) : .unchanged
    case .base: conflict == .open ? .tinted(.conflict) : .original
    }
  }
}

/// Lays out lines on a grid, row after row.
private struct Builder {
  private var rows: [String] = []
  private var lineNumbers: [Int32] = []
  private var blocks: [PaneBlock] = []
  private var nextLine: Int32 = 0

  var content: PaneContent {
    PaneContent(
      text: rows.joined(separator: "\n"), lineNumbers: lineNumbers.isEmpty ? [-1] : lineNumbers,
      blocks: blocks)
  }

  mutating func appendUnchanged(_ lines: [String]) {
    appendRows(lines, rowCount: lines.count)
  }

  mutating func append(
    _ lines: [String], rowCount: Int, style: BlockStyle, marker: Marker? = nil,
    conflict: ConflictMarker? = nil
  ) {
    guard rowCount > 0 else { return }
    let first = rows.count
    appendRows(lines, rowCount: rowCount)
    blocks.append(
      PaneBlock(rows: first..<rows.count, style: style, marker: marker, conflict: conflict))
  }

  private mutating func appendRows(_ lines: [String], rowCount: Int) {
    for line in lines {
      rows.append(line)
      lineNumbers.append(nextLine)
      nextLine += 1
    }
    for _ in lines.count..<rowCount {
      rows.append("")
      lineNumbers.append(-1)
    }
  }
}
