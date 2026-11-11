import Foundation
import Testing

@testable import MergeEngine

@Suite("Token diff")
struct TokenDiffTests {
  private func tokens(_ buffer: TokenBuffer) -> [String] {
    (0..<buffer.tokenCount).map { buffer.token($0).text }
  }

  private func changedText(_ diff: TokenDiff) -> [(removed: String, added: String)] {
    diff.changes.map {
      (diff.a.bytes(tokens: $0.a.tokens).text, diff.b.bytes(tokens: $0.b.tokens).text)
    }
  }

  @Test("Blocks cover both inputs in order and rebuild them")
  func blocksCoverInputs() throws {
    let a = Data("let value = compute(1, 2);\n")
    let b = Data("let total = compute(1, 22);\n")
    let diff = try TokenDiff(a, b)

    var next = (a: 0, b: 0)
    var rebuilt = (a: Data(), b: Data())
    for block in diff.blocks {
      #expect(block.a.tokens.lowerBound == next.a && block.b.tokens.lowerBound == next.b)
      next = (block.a.tokens.upperBound, block.b.tokens.upperBound)
      rebuilt.a += diff.a.bytes(tokens: block.a.tokens)
      rebuilt.b += diff.b.bytes(tokens: block.b.tokens)
    }
    #expect(next == (diff.a.tokenCount, diff.b.tokenCount))
    #expect(rebuilt.a == a)
    #expect(rebuilt.b == b)
  }

  @Test("Only the changed words of a line are reported")
  func changedWords() throws {
    let diff = try TokenDiff(
      Data("let value = compute(1, 2);\n"), Data("let total = compute(1, 22);\n"))
    #expect(changedText(diff).map(\.removed) == ["value", "2"])
    #expect(changedText(diff).map(\.added) == ["total", "22"])
  }

  @Test("Character classes: word, whitespace and punctuation runs; CRLF is one token")
  func characterClassTokens() throws {
    let diff = try TokenDiff(Data("ab  cd;;\r\n"), Data("ab  cd;;\r\n"))
    #expect(tokens(diff.a) == ["ab", "  ", "cd", ";;", "\r\n"])
    #expect(diff.isIdentical)
  }

  @Test("Bytes above 0x7F belong to words")
  func nonASCIIBytesAreWordCharacters() throws {
    let cologne = Data([0x4B, 0xF6, 0x6C, 0x6E])  // "Köln" in Latin-1
    let munich = Data([0x4D, 0xFC, 0x6E, 0x63, 0x68, 0x65, 0x6E])  // "München"
    let diff = try TokenDiff(
      Data("aus ") + cologne + Data("\n"), Data("aus ") + munich + Data("\n"))
    #expect(diff.changes.count == 1)
    #expect(diff.changes.first.map { diff.a.bytes(tokens: $0.a.tokens) } == cologne)
    #expect(diff.changes.first.map { diff.b.data.subdata(in: $0.b.byteRange) } == munich)
  }

  @Test("Word granularity splits after each whitespace byte")
  func wordTokens() throws {
    let diff = try TokenDiff(Data("one two three"), Data("one TWO three"), granularity: .words)
    #expect(tokens(diff.a) == ["one ", "two ", "three"])
    #expect(diff.changes.map(\.a.tokens) == [1..<2])
  }
}
