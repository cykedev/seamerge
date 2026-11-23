import CryptoKit
import Foundation

/// What identifies a merge across launches: the content of its base, A and B, whatever their
/// paths.
///
/// Git hands a merge tool new temporary copies with other names on every run, so the key looks at
/// the bytes alone. Two merges of the same three contents get the same key; a change of a single
/// byte in any input gives another.
public struct MergeKey: Sendable, Hashable {
  /// The key as 64 lowercase hexadecimal digits, which also serve as a file name.
  public let rawValue: String

  /// The length that stands for a missing base; no content is that long.
  private static let missingBase = UInt64.max

  /// The key of a merge of `inputs`.
  ///
  /// The key is the SHA-256 digest of the bytes of the base, A and B in that order, each preceded
  /// by its length, so that no two different triples run together into the same bytes. A merge
  /// without a base has a fixed mark in place of the base, which no base, not even an empty one,
  /// has. Hashing takes time in proportion to the size of the files.
  public init(_ inputs: Session.Inputs<SourceFile>) {
    var hasher = SHA256()
    func update(length: UInt64) {
      withUnsafeBytes(of: length.littleEndian) { hasher.update(bufferPointer: $0) }
    }
    if let base = inputs.base {
      update(length: UInt64(base.bytes.count))
      hasher.update(data: base.bytes)
    } else {
      update(length: Self.missingBase)
    }
    for file in [inputs.a, inputs.b] {
      update(length: UInt64(file.bytes.count))
      hasher.update(data: file.bytes)
    }
    rawValue = Self.hexadecimal(hasher.finalize())
  }

  /// The key whose ``rawValue`` is `rawValue`, or `nil` if it is not 64 lowercase hexadecimal
  /// digits.
  public init?(rawValue: String) {
    let digits = rawValue.utf8
    guard digits.count == SHA256.byteCount * 2,
      digits.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) })
    else { return nil }
    self.rawValue = rawValue
  }

  /// `bytes` as lowercase hexadecimal digits, two for each byte.
  static func hexadecimal(_ bytes: some Sequence<UInt8>) -> String {
    let digits = Array("0123456789abcdef".utf8)
    var text: [UInt8] = []
    for byte in bytes {
      text.append(digits[Int(byte >> 4)])
      text.append(digits[Int(byte & 0x0F)])
    }
    return String(decoding: text, as: UTF8.self)
  }
}
