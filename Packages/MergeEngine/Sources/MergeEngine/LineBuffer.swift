import Foundation

/// An input of a diff or merge together with the engine's split of it into
/// lines.
///
/// The split depends on the comparison mode (see ``Whitespace``), so line
/// positions must always be taken from the result, not computed separately.
public struct LineBuffer: Sendable, Hashable {
  /// The input bytes.
  public let data: Data

  /// Byte offset where each line starts, followed by `data.count`.
  let offsets: [Int]

  init(data: Data, offsets: [Int]) {
    self.data = data.zeroBased
    self.offsets = offsets
  }

  /// The number of lines.
  public var lineCount: Int { offsets.count - 1 }

  /// The byte range of `lines`, including the line ending of the last one.
  ///
  /// - Precondition: `lines` lies within `0...lineCount`.
  public func byteRange(lines: Range<Int>) -> Range<Int> {
    offsets[lines.lowerBound]..<offsets[lines.upperBound]
  }

  /// The bytes of `lines`, including the line ending of the last one.
  ///
  /// - Precondition: `lines` lies within `0...lineCount`.
  public func bytes(lines: Range<Int>) -> Data {
    data.subdata(in: byteRange(lines: lines))
  }

  /// The bytes of one line, including its line ending.
  ///
  /// - Precondition: `index` lies within `0..<lineCount`.
  public func line(_ index: Int) -> Data {
    bytes(lines: index..<index + 1)
  }
}

/// A range of one input of a diff or merge, in lines and in bytes.
public struct Span: Sendable, Hashable {
  /// The lines, as zero-based indices.
  public let lines: Range<Int>

  /// The bytes of ``lines``, as offsets into the input.
  public let byteRange: Range<Int>

  init(lines: Range<Int>, in buffer: LineBuffer) {
    self.lines = lines
    self.byteRange = buffer.byteRange(lines: lines)
  }

  public var isEmpty: Bool { lines.isEmpty }
}
