import Foundation

@testable import MergeEngine

/// Line equality under a whitespace mode, written from the documented
/// meaning of the Perforce flags rather than from the engine's code, so that
/// the tests can check the engine against it.
///
/// One rule comes from the engine's implementation and is pinned by its own
/// test: with `-dl`, a last line without a line ending equals the same line
/// ending in LF or CR, but not one ending in CRLF (DifflReader::Equal accepts
/// exactly one remaining newline byte).
func linesEqual(_ x: Data, _ y: Data, under mode: Whitespace) -> Bool {
  guard normalized(x, mode) == normalized(y, mode) else { return false }
  if mode == .ignoreLineEndings {
    let crlf = Data("\r\n")
    func lacksLineEnding(_ line: Data) -> Bool {
      line.last != UInt8(ascii: "\n") && line.last != UInt8(ascii: "\r")
    }
    if lacksLineEnding(x) && y.suffix(2) == crlf || lacksLineEnding(y) && x.suffix(2) == crlf {
      return false
    }
  }
  return true
}

private func normalized(_ line: Data, _ mode: Whitespace) -> [UInt8] {
  let space = UInt8(ascii: " ")
  let tab = UInt8(ascii: "\t")
  var bytes = [UInt8](line)
  if mode != .exact {
    while bytes.last == UInt8(ascii: "\n") || bytes.last == UInt8(ascii: "\r") {
      bytes.removeLast()
    }
  }
  switch mode {
  case .exact, .ignoreLineEndings:
    return bytes
  case .ignoreAmount:
    // Each run of spaces and tabs becomes one space; a trailing run vanishes.
    var output: [UInt8] = []
    var pendingSpace = false
    for byte in bytes {
      if byte == space || byte == tab {
        pendingSpace = true
        continue
      }
      if pendingSpace { output.append(space) }
      pendingSpace = false
      output.append(byte)
    }
    return output
  case .ignoreAll:
    return bytes.filter { $0 != space && $0 != tab }
  }
}

/// Whether two spans hold the same lines under `mode`.
func spansEqual(
  _ spanX: LineSpan, in x: LineBuffer, _ spanY: LineSpan, in y: LineBuffer, under mode: Whitespace
) -> Bool {
  spanX.lines.count == spanY.lines.count
    && zip(spanX.lines, spanY.lines).allSatisfy { lineX, lineY in
      linesEqual(x.line(lineX), y.line(lineY), under: mode)
    }
}

/// The text Perforce's `DiffMerge::Read()` would produce for `merge`,
/// rebuilt from its blocks: unchanged text from the base, one-sided changes
/// from the changed side, identical changes from A, conflicts as A then B.
func readStream(of merge: Merge) -> Data {
  merge.blocks.reduce(into: Data()) { output, block in
    switch block.kind {
    case .unchanged: output += merge.base.bytes(lines: block.base.lines)
    case .changedInA, .changedInBoth: output += merge.a.bytes(lines: block.a.lines)
    case .changedInB: output += merge.b.bytes(lines: block.b.lines)
    case .conflict:
      output += merge.a.bytes(lines: block.a.lines)
      output += merge.b.bytes(lines: block.b.lines)
    }
  }
}
