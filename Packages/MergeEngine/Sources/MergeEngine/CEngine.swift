import CMergeEngine
import Foundation

// Glue between the Swift API and CMergeEngine.h. The C functions that read the
// inputs are called inside withUnsafeBytes, so the input pointers are valid
// for the whole call; results are copied into Swift values before their
// handles are destroyed.

extension Whitespace {
  var sequence: me_sequence {
    switch self {
    case .exact: ME_SEQUENCE_LINES
    case .ignoreLineEndings: ME_SEQUENCE_LINES_IGNORE_EOL
    case .ignoreAmount: ME_SEQUENCE_LINES_IGNORE_SPACE
    case .ignoreAll: ME_SEQUENCE_LINES_IGNORE_ALL_SPACE
    }
  }
}

extension TokenGranularity {
  var sequence: me_sequence {
    switch self {
    case .characterClasses: ME_SEQUENCE_CHARACTER_CLASSES
    case .words: ME_SEQUENCE_WORDS
    }
  }
}

extension MergeStrategy {
  var grid: me_grid {
    switch self {
    case .optimal: ME_GRID_OPTIMAL
    case .guarded: ME_GRID_GUARDED
    case .diff3: ME_GRID_DIFF3
    case .guardedDiff3: ME_GRID_GUARDED_DIFF3
    case .twoWay: ME_GRID_TWO_WAY
    }
  }
}

func check(_ status: me_status) throws(EngineError) {
  switch status {
  case ME_OK: return
  case ME_ERROR_INPUT_TOO_LARGE: throw .inputTooLarge
  case ME_ERROR_OUT_OF_MEMORY: throw .outOfMemory
  default: throw .internalFailure
  }
}

func offsets(_ pointer: UnsafePointer<Int64>?, count: Int) throws(EngineError) -> [Int] {
  guard let pointer, count > 0 else { throw .internalFailure }
  return UnsafeBufferPointer(start: pointer, count: count).map { Int($0) }
}

/// A view of `count` elements at `pointer`.
///
/// The view is only valid while the handle that owns the elements is alive.
func elements<Element>(
  _ pointer: UnsafePointer<Element>?, count: Int
) -> UnsafeBufferPointer<Element> {
  UnsafeBufferPointer(start: count > 0 ? pointer : nil, count: count)
}

/// Calls `body` with base address and length of each buffer.
///
/// Empty buffers may have a nil base address, which the C interface accepts.
func withBytes<R>(
  _ x: Data, _ y: Data,
  _ body: (UnsafeRawPointer?, Int, UnsafeRawPointer?, Int) -> R
) -> R {
  x.withUnsafeBytes { px in
    y.withUnsafeBytes { py in
      body(px.baseAddress, px.count, py.baseAddress, py.count)
    }
  }
}

func withBytes<R>(
  _ x: Data, _ y: Data, _ z: Data,
  _ body: (UnsafeRawPointer?, Int, UnsafeRawPointer?, Int, UnsafeRawPointer?, Int) -> R
) -> R {
  x.withUnsafeBytes { px in
    withBytes(y, z) { py, ly, pz, lz in
      body(px.baseAddress, px.count, py, ly, pz, lz)
    }
  }
}

/// Output of Perforce's own `DiffMerge::Read()` for the same merge, used to
/// verify ``Merge``.
///
/// A conflict contributes A's lines, then B's lines.
func referenceMergeText(
  base: Data, a: Data, b: Data, whitespace: Whitespace, strategy: MergeStrategy
) throws(EngineError) -> (text: Data, conflictCount: Int) {
  var text: UnsafeMutableRawPointer?
  var length = 0
  var conflicts = 0
  let status = withBytes(base, a, b) { p0, l0, pa, la, pb, lb in
    me_merge_reference_text(
      p0, l0, pa, la, pb, lb, whitespace.sequence, strategy.grid, &text, &length, &conflicts)
  }
  defer { free(text) }
  try check(status)
  return (text.map { Data(bytes: $0, count: length) } ?? Data(), conflicts)
}

/// The engine's two-way comparison, before it is wrapped in ``Diff`` or
/// ``TokenDiff``.
///
/// Ranges are element indices.
struct TwoWayComparison {
  struct Block {
    let isEqual: Bool
    let a: Range<Int>
    let b: Range<Int>
  }

  let offsetsA: [Int]
  let offsetsB: [Int]
  let blocks: [Block]

  init(_ a: Data, _ b: Data, sequence: me_sequence) throws(EngineError) {
    var handle: OpaquePointer?
    let status = withBytes(a, b) { pa, la, pb, lb in
      me_diff_create(pa, la, pb, lb, sequence, &handle)
    }
    defer { me_diff_destroy(handle) }
    try check(status)

    var count = 0
    offsetsA = try offsets(me_diff_offsets(handle, ME_DIFF_SIDE_A, &count), count: count)
    offsetsB = try offsets(me_diff_offsets(handle, ME_DIFF_SIDE_B, &count), count: count)
    blocks = elements(me_diff_blocks(handle, &count), count: count).map { block in
      Block(
        isEqual: block.kind == ME_DIFF_EQUAL,
        a: Int(block.a_start)..<Int(block.a_end),
        b: Int(block.b_start)..<Int(block.b_end))
    }
  }
}

extension Data {
  /// The same bytes with `startIndex == 0`, so that offsets can be used as
  /// indices.
  var zeroBased: Data { startIndex == 0 ? self : Data(self) }
}
