import Foundation
import PaneKit

/// The result of a merge of real code with a block in every state that the decision column
/// shows, an open conflict among them with its preview.
struct SampleResult {
  /// A run of lines that no side changed, or a block with its decision.
  enum Entry {
    case same([String])
    case block([String], style: BlockStyle, decision: BlockDecision)
    /// An open conflict: the preview of A's lines, then of B's.
    case conflict(a: [String], b: [String], decision: BlockDecision)
  }

  let entries: [Entry]

  /// The content of the result pane and the decision of each block.
  func content() -> (content: PaneContent, decisions: [Int: BlockDecision]) {
    var lines: [String] = []
    var blocks: [PaneBlock] = []
    var previews: [PanePreview] = []
    var decisions: [Int: BlockDecision] = [:]
    var offset = 0
    func append(_ newLines: [String]) {
      for line in newLines {
        lines.append(line)
        offset += line.utf16.count + 1
      }
    }
    for entry in entries {
      switch entry {
      case .same(let newLines):
        append(newLines)
      case .block(let newLines, let style, let decision):
        decisions[blocks.count] = decision
        blocks.append(PaneBlock(rows: lines.count..<lines.count + newLines.count, style: style))
        append(newLines)
      case .conflict(let a, let b, let decision):
        decisions[blocks.count] = decision
        blocks.append(
          PaneBlock(rows: lines.count..<lines.count + a.count + b.count, style: .tinted(.conflict)))
        for (side, sideLines) in [(ColorRole.a, a), (.b, b)] {
          let start = offset
          append(sideLines)
          previews.append(PanePreview(range: start..<offset, role: side))
        }
      }
    }
    let content = PaneContent(
      text: lines.joined(separator: "\n"), lineNumbers: lines.indices.map { Int32($0) },
      blocks: blocks, previews: previews)
    return (content, decisions)
  }

  /// The index of the block of each state, as the pictures and tests name them.
  enum Block: Int, CaseIterable {
    case automaticA, automaticB, nothingTaken, automaticBoth, chosenA, chosenB, chosenBase
    case chosenAThenB, chosenBThenA, edited, open
  }

  /// The sample: the start of `Transcoder.swift` from TextIO, merged.
  static let transcoder = SampleResult(entries: [
    .same(["import Foundation", ""]),
    .block(
      ["/// Converts between bytes in a ``TextEncoding`` and strings without losing anything."],
      style: .tinted(.a),
      decision: decision(.automatic([.a]), toggles: [([.a], true), ([.base, .b], false)])),
    .same(["enum Transcoder {"]),
    .block(
      [
        "  /// The encodings that every conversion supports.",
        "  static let supportedEncodings = TextEncoding.allCases",
      ],
      style: .tinted(.b),
      decision: decision(.automatic([.b]), toggles: [([.base, .a], false), ([.b], true)])),
    // B removed the documentation of `decode`, and the user took nothing.
    .same([""]),
    .block(
      [], style: .unchanged,
      decision: BlockDecision(
        state: .chosen([]),
        toggles: [
          toggle([.base, .a], isOn: false),
          DecisionToggle(
            roles: [.b], isOn: false, isDeletion: true, help: "Remove these lines, as main did."),
        ], canReset: true)),
    .same([
      "  static func decode(_ bytes: Data, from encoding: TextEncoding) -> String? {",
      "    switch encoding {", "    case .utf8:",
    ]),
    .block(
      ["      return String(validating: bytes, as: Unicode.UTF8.self)"], style: .combined,
      decision: decision(.automatic([.a, .b]), toggles: [([.a, .b], true), ([.base], false)])),
    .same(["    case .utf16LittleEndian:"]),
    .block(
      ["      return decode(bytes, as: UTF16.self, bigEndian: false)"], style: .tinted(.a),
      decision: decision(
        .chosen([.a]), toggles: [([.a], true), ([.base], false), ([.b], false)], canReset: true)),
    .same(["    case .utf16BigEndian:"]),
    .block(
      ["      return decode(bytes, as: UTF16.self, bigEndian: true)"], style: .tinted(.b),
      decision: decision(
        .chosen([.b]), toggles: [([.a], false), ([.base], false), ([.b], true)], canReset: true)),
    .same(["    case .utf32LittleEndian:"]),
    .block(
      ["      return decode(bytes, as: UTF32.self, bigEndian: false)"], style: .original,
      decision: decision(
        .chosen([.base]), toggles: [([.a], false), ([.base], true), ([.b], false)],
        canReset: true)),
    .same(["    case .windows1252, .isoLatin1, .macRoman:"]),
    .block(
      [
        "      guard let legacyEncoding = encoding.singleByteFoundationEncoding,",
        "      guard let foundationEncoding = encoding.singleByteFoundationEncoding,",
      ], style: .tinted(.a),
      decision: decision(
        .chosen([.a, .b]), toggles: [([.a], true), ([.base], false), ([.b], true)],
        canReset: true)),
    .block(
      [
        "        let text = String(bytes, encoding: foundationEncoding),",
        "        let text = String(data: bytes, encoding: legacyEncoding),",
      ], style: .tinted(.b),
      decision: decision(
        .chosen([.b, .a]), toggles: [([.a], true), ([.base], false), ([.b], true)],
        canReset: true)),
    .block(
      ["        text.data(using: foundationEncoding) == bytes"], style: .handwritten,
      decision: decision(
        .edited, toggles: [([.a], false), ([.base], false), ([.b], false)], canReset: true)),
    .same(["      else { return nil }"]),
    .conflict(
      a: ["      return text.isEmpty ? nil : text"],
      b: ["      guard !text.isEmpty else { return nil }", "      return text"],
      decision: decision(.open, toggles: [([.a], false), ([.base], false), ([.b], false)])),
    .same(["    }", "  }", "}"]),
  ])

  /// What the column shows for a block in `state` with toggles of the given inputs.
  private static func decision(
    _ state: BlockDecision.State, toggles: [([ColorRole], Bool)], canReset: Bool = false
  ) -> BlockDecision {
    BlockDecision(
      state: state, toggles: toggles.map { toggle($0.0, isOn: $0.1) }, canReset: canReset)
  }

  /// A toggle of `roles` with the sentence that names the branch of each side.
  static func toggle(_ roles: [ColorRole], isOn: Bool) -> DecisionToggle {
    let help: String
    switch roles.filter({ $0 != .base }) {
    case [.a]: help = "Take the version of feature/login."
    case [.b]: help = "Take the version of main."
    case [.a, .b]: help = "Take the version of feature/login and main."
    default: help = "Take the version of the base."
    }
    return DecisionToggle(roles: roles, isOn: isOn, help: help)
  }
}
