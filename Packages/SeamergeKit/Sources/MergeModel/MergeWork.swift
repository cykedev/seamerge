import CryptoKit
public import Foundation

/// The work done in the result of a merge, kept so that it can be put back when the same merge
/// opens again: the text and the decision of every block, the comparison mode, the format of the
/// result and the current block.
///
/// The work holds the result text without the previews of open conflicts, because a preview
/// shows the names of the sides, which may differ the next time; restoring shows the previews of
/// the new result. The undo stack is not kept.
///
/// Capturing the work and coding it take time in proportion to the size of the result, so both
/// belong off the main actor; the main actor only takes the document and the text, which are
/// values.
public struct MergeWork: Sendable, Hashable {
  /// The version of the format that ``MergeWork`` encodes; a file with another version is none
  /// that this version of the app can read.
  public static let formatVersion = 1

  /// The merge the work belongs to.
  public let key: MergeKey

  /// When the work was captured.
  public let savedAt: Date

  /// The comparison mode of the window.
  public let mode: ComparisonMode

  /// The encoding, byte order mark and line ending the result is written in.
  public let format: ResultFormat

  /// The result text without the previews of open conflicts: the text of every other segment,
  /// in order.
  let text: String

  /// The fingerprint of the blocks of the comparison, as ``fingerprint(of:)`` gives it.
  let blockFingerprint: String

  /// The segment of each block, in the order of the blocks.
  let segments: [SavedSegment]

  /// The block the cursor was in, if any.
  let currentBlock: BlockPlace?

  /// A segment of the result as the work keeps it.
  struct SavedSegment: Sendable, Hashable {
    /// The length of the segment's text in ``MergeWork/text``, in UTF-16 code units, or `nil`
    /// for an open conflict, whose preview the text leaves out.
    var length: Int?

    /// The decision of the block, or `nil` if the block is as it was after loading.
    var decision: Decision?
  }

  /// The decision of a block that differs from how it was after loading.
  struct Decision: Sendable, Hashable {
    /// The state of the segment; never ``Segment/State/open``, which only a conflict as loaded
    /// has.
    var state: Segment.State

    /// The sources of the segment.
    var sources: [Role]

    /// The bytes the block covers in base, A and B, by which a block of another comparison of the
    /// same files is the same block.
    var byteRanges: [Range<Int>]
  }

  /// Where a block is: its position among the blocks and the bytes it covers in base, A and B.
  struct BlockPlace: Sendable, Hashable {
    var index: Int
    var byteRanges: [Range<Int>]
  }

  /// Creates work from its parts, as decoding does.
  init(
    key: MergeKey, savedAt: Date, mode: ComparisonMode, format: ResultFormat, text: String,
    blockFingerprint: String, segments: [SavedSegment], currentBlock: BlockPlace?
  ) {
    self.key = key
    self.savedAt = savedAt
    self.mode = mode
    self.format = format
    self.text = text
    self.blockFingerprint = blockFingerprint
    self.segments = segments
    self.currentBlock = currentBlock
  }

  /// The work in `document` with `text`, or `nil` if every block is as it was after loading, so
  /// that there is nothing to keep.
  ///
  /// - Parameters:
  ///   - document: The result of the merge.
  ///   - text: The result text, as long as the segments of `document` together.
  ///   - key: The key of the merge, which the caller computes once when the merge opens.
  ///   - format: The format the result is written in.
  ///   - currentBlock: The block the cursor is in, if any.
  ///   - savedAt: The time of the capture.
  /// - Precondition: `text` is as long as the segments of `document` together, and
  ///   `currentBlock` belongs to its session.
  public init?(
    capturing document: ResultDocument, text: String, key: MergeKey, format: ResultFormat,
    currentBlock: Block?, savedAt: Date
  ) {
    guard document.canResetAll else { return nil }
    let session = document.session
    var keptText = ""
    var segments: [SavedSegment] = []
    segments.reserveCapacity(document.segments.count)
    for (index, segmentText) in document.split(text).enumerated() {
      let segment = document.segments[index]
      var saved = SavedSegment()
      if segment.state != .open {
        keptText += segmentText
        saved.length = segment.length
      }
      if document.differsFromInitial(index) {
        saved.decision = Decision(
          state: segment.state, sources: segment.sources,
          byteRanges: session.byteRanges(of: session.blocks[index]))
      }
      segments.append(saved)
    }
    self.init(
      key: key, savedAt: savedAt, mode: session.options.mode, format: format, text: keptText,
      blockFingerprint: Self.fingerprint(of: session), segments: segments,
      currentBlock: currentBlock.map { block in
        BlockPlace(
          index: document.index(of: block), byteRanges: session.byteRanges(of: block))
      })
  }

  /// The fingerprint of the blocks of `session`: the SHA-256 digest of their kinds and of the
  /// bytes each covers in base, A and B, as 64 lowercase hexadecimal digits.
  ///
  /// Together with the content of the files, which the ``key`` covers, the blocks decide the
  /// result as it is after loading. Two comparisons with the same fingerprint therefore have the
  /// same segments, and work moves between them block for block. Bytes rather than line numbers
  /// count, because comparison modes split a file at different line endings.
  static func fingerprint(of session: Session) -> String {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(8 + session.blocks.count * 56)
    func append(_ value: Int) {
      withUnsafeBytes(of: UInt64(value).littleEndian) { bytes.append(contentsOf: $0) }
    }
    append(session.blocks.count)
    for block in session.blocks {
      append(block.kind.fingerprintCode)
      for range in session.byteRanges(of: block) {
        append(range.lowerBound)
        append(range.upperBound)
      }
    }
    return MergeKey.hexadecimal(SHA256.hash(data: bytes))
  }
}

extension Block.Kind {
  /// The number that stands for the kind in a fingerprint; it never changes, so that a
  /// fingerprint stays the same across versions of the app.
  fileprivate var fingerprintCode: Int {
    switch self {
    case .unchanged: 0
    case .changedInA: 1
    case .changedInB: 2
    case .changedInBoth: 3
    case .conflict: 4
    case .changed: 5
    }
  }
}
