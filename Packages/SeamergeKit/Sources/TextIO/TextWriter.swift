import Foundation
import os

/// Writes text to a file with one encoding and one line ending.
public struct TextWriter: Sendable {
  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "TextIO")

  /// The encoding the file is written in.
  public let encoding: TextEncoding

  /// Whether the file starts with the byte order mark of ``encoding``.
  public let writesByteOrderMark: Bool

  /// The line ending every line break is written as.
  public let lineEnding: LineEnding

  /// Creates a writer for the given form of a file.
  ///
  /// - Precondition: `writesByteOrderMark` is only `true` for an encoding that
  ///   ``TextEncoding/supportsByteOrderMark``.
  public init(encoding: TextEncoding, writesByteOrderMark: Bool, lineEnding: LineEnding) {
    precondition(
      !writesByteOrderMark || encoding.supportsByteOrderMark,
      "\(encoding) has no byte order mark")
    self.encoding = encoding
    self.writesByteOrderMark = writesByteOrderMark
    self.lineEnding = lineEnding
  }

  /// The bytes of a file holding `text`.
  ///
  /// Every line feed, carriage return and pair of both becomes ``lineEnding``. Line breaks are
  /// neither added nor removed, so a text without a final line break is written without one.
  ///
  /// - Throws: ``TextIOError/unrepresentableText(_:)`` if ``encoding`` cannot represent every
  ///   character of `text`.
  public func encode(_ text: String) throws(TextIOError) -> Data {
    guard let encoded = Transcoder.encode(utf8: unifyingLineEndings(of: text), to: encoding) else {
      throw .unrepresentableText(encoding)
    }
    var bytes = Data(writesByteOrderMark ? encoding.byteOrderMark ?? [] : [])
    bytes.append(contentsOf: encoded)
    return bytes
  }

  /// Writes `text` to the file at `url`, encoded as ``encode(_:)`` describes.
  ///
  /// The file is replaced atomically: readers see either the old or the new content. An existing
  /// file keeps its permissions and other metadata; a symbolic link is followed, so the file it
  /// points to is replaced.
  ///
  /// - Throws: ``TextIOError/unrepresentableText(_:)`` before anything is written, or the error of
  ///   the file system if the file cannot be written.
  public func write(_ text: String, to url: URL) throws {
    try write(encode(text), to: url)
  }

  /// Writes `bytes`, the content of a file as ``encode(_:)`` gives it, to the file at `url`.
  ///
  /// The file is replaced atomically and keeps its permissions and other metadata, as with
  /// text; a symbolic link is followed.
  ///
  /// - Throws: The error of the file system if the file cannot be written.
  public func write(_ bytes: Data, to url: URL) throws {
    let destination = url.resolvingSymlinksInPath()
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else {
      try bytes.write(to: destination, options: .atomic)
      return
    }
    // Swapping in a file written next to the original keeps the original's extended attributes,
    // such as Finder tags, which an atomic `Data.write` drops.
    let scratchDirectory = try fileManager.url(
      for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination,
      create: true)
    defer {
      do {
        try fileManager.removeItem(at: scratchDirectory)
      } catch {
        Self.logger.error(
          "Could not remove \(scratchDirectory.path, privacy: .public): \(error, privacy: .public)")
      }
    }
    let replacement = scratchDirectory.appending(path: destination.lastPathComponent)
    try bytes.write(to: replacement)
    _ = try fileManager.replaceItemAt(destination, withItemAt: replacement)
  }

  private func unifyingLineEndings(of text: String) -> [UInt8] {
    var text = text
    return text.withUTF8 { source in
      let replacement = lineEnding.utf8
      var unified: [UInt8] = []
      unified.reserveCapacity(source.count)
      var index = 0
      while index < source.count {
        let byte = source[index]
        if byte == ASCII.lineFeed || byte == ASCII.carriageReturn {
          unified.append(contentsOf: replacement)
          let isPair =
            byte == ASCII.carriageReturn && index + 1 < source.count
            && source[index + 1] == ASCII.lineFeed
          index += isPair ? 2 : 1
        } else {
          unified.append(byte)
          index += 1
        }
      }
      return unified
    }
  }
}
