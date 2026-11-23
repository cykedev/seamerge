import Foundation
import MergeModel
import Testing
import TextBasics

extension ResultBuffer {
  /// The work in the buffer as it comes back after encoding and decoding it, or `nil` if there
  /// is nothing to keep.
  ///
  /// The result is written with CRLF line endings, so that the format differs from the one a
  /// result is loaded with.
  func capturedWork(currentBlock: Block? = nil) throws -> MergeWork? {
    let session = document.session
    var format = ResultFormat(resultOf: session)
    format.lineEnding = .crlf
    guard
      let work = MergeWork(
        capturing: document, text: text, key: MergeKey(session.inputs), format: format,
        currentBlock: currentBlock, savedAt: Date(timeIntervalSinceReferenceDate: 812_345_678.25))
    else { return nil }
    let decoded = try JSONDecoder().decode(MergeWork.self, from: JSONEncoder().encode(work))
    #expect(decoded == work)
    return decoded
  }

  /// A buffer with the result of `session` as loaded, into which `work` is restored as one undo
  /// step, and the restoration.
  static func restoring(
    _ work: MergeWork, into session: Session, removalNotes: [Role: String] = [:]
  ) throws -> (buffer: ResultBuffer, restoration: WorkRestoration) {
    var buffer = ResultBuffer(session, removalNotes: removalNotes)
    let restoration = try #require(buffer.document.planRestoring(work))
    buffer.perform(restoration.plan)
    return (buffer, restoration)
  }
}
