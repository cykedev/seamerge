import Foundation
import TextIO

/// How the result of a merge is written: its encoding, whether it starts with a byte order mark,
/// and the one line ending every line break becomes.
public struct ResultFormat: Sendable, Hashable {
  /// A line ending the result can be written with.
  public enum LineEnding: Sendable, Hashable, CaseIterable {
    /// A line feed, as on macOS and Linux.
    case lf

    /// A carriage return followed by a line feed, as on Windows.
    case crlf

    /// A carriage return alone, as on classic Mac OS.
    case cr

    /// The line ending as TextIO describes it.
    init(_ lineEnding: TextIO.LineEnding) {
      self =
        switch lineEnding {
        case .lf: .lf
        case .crlf: .crlf
        case .cr: .cr
        }
    }

    /// The line ending as TextIO describes it.
    var textLineEnding: TextIO.LineEnding {
      switch self {
      case .lf: .lf
      case .crlf: .crlf
      case .cr: .cr
      }
    }
  }

  /// The encoding the result is written in.
  public private(set) var encoding: FileEncoding

  /// Whether the result starts with the byte order mark of ``encoding``.
  public private(set) var writesByteOrderMark: Bool

  /// The line ending every line break of the result is written as.
  public var lineEnding: LineEnding

  /// Creates a format.
  ///
  /// - Precondition: `writesByteOrderMark` is only `true` for an encoding that
  ///   ``FileEncoding/supportsByteOrderMark``.
  public init(encoding: FileEncoding, writesByteOrderMark: Bool, lineEnding: LineEnding) {
    precondition(
      !writesByteOrderMark || encoding.supportsByteOrderMark, "\(encoding) has no byte order mark")
    self.encoding = encoding
    self.writesByteOrderMark = writesByteOrderMark
    self.lineEnding = lineEnding
  }

  /// The format the result of `session` is written in unless the user chooses another: that of
  /// B.
  ///
  /// The encoding and the byte order mark are those of the first input that is text, in the
  /// order B, A, base; the line ending is the predominant one of the first input that has line
  /// breaks, in the same order, and LF if none has.
  public init(resultOf session: Session) {
    let order: [Role] = [.b, .a, .base]
    let text = order.lazy.compactMap { session.file(for: $0) }.first { !$0.isBinary }
    encoding = text?.encoding ?? .utf8
    writesByteOrderMark = text?.hasByteOrderMark ?? false
    lineEnding =
      order.lazy.compactMap { session.file(for: $0)?.predominantLineEnding }.first ?? .lf
  }

  /// This format with `encoding`: a Unicode encoding other than UTF-8 starts with its byte order
  /// mark, so that readers can tell the order of its bytes; UTF-8 keeps the mark only if this
  /// format writes it in UTF-8 already.
  public func with(encoding: FileEncoding) -> ResultFormat {
    let keepsMark = encoding == .utf8 && self.encoding == .utf8 && writesByteOrderMark
    return ResultFormat(
      encoding: encoding,
      writesByteOrderMark: encoding == .utf8 ? keepsMark : encoding.supportsByteOrderMark,
      lineEnding: lineEnding)
  }

  /// The bytes of a result file holding `text`.
  ///
  /// Every line break becomes ``lineEnding``; a text without a final line break is written
  /// without one.
  ///
  /// - Throws: ``MergeModelError/unrepresentableText(_:)`` if ``encoding`` cannot represent
  ///   every character of `text`.
  public func encode(_ text: String) throws(MergeModelError) -> Data {
    do {
      return try writer.encode(text)
    } catch {
      throw .unrepresentableText(encoding)
    }
  }

  /// Writes `text`, encoded as ``encode(_:)`` describes, to the file at `url`, and returns the
  /// bytes written.
  ///
  /// The file is replaced atomically, so that a failure leaves the file as it was; an existing
  /// file keeps its permissions.
  ///
  /// - Throws: ``MergeModelError/unrepresentableText(_:)`` before anything is written, or
  ///   ``MergeModelError/writingFailed(path:reason:)`` if the file cannot be written.
  @discardableResult
  public func write(_ text: String, to url: URL) throws(MergeModelError) -> Data {
    let bytes = try encode(text)
    do {
      try writer.write(bytes, to: url)
      return bytes
    } catch {
      throw .writingFailed(
        path: url.path(percentEncoded: false), reason: error.localizedDescription)
    }
  }

  private var writer: TextWriter {
    TextWriter(
      encoding: encoding.textEncoding, writesByteOrderMark: writesByteOrderMark,
      lineEnding: lineEnding.textLineEnding)
  }
}
