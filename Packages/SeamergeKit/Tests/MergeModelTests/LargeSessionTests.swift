import Foundation
import MergeModel
import Testing

struct LargeSessionTests {
  static let lineCount = 100_000

  /// A line of source code with characters of every UTF-8 length.
  static func line(_ number: Int, _ variant: String = "") -> String {
    "let välue\(number) = compute(\(number)) // 東京 😀 \(variant)\n"
  }

  /// The base and two sides of 100 000 lines each: A changes every 97th line and inserts a line
  /// after every 1000th, B changes every 89th line and deletes every 1500th.
  static func inputs() -> (base: Data, a: Data, b: Data) {
    var base = ""
    var a = ""
    var b = ""
    for number in 0..<lineCount {
      base += line(number)
      a += line(number, number % 97 == 0 ? "changed in a" : "")
      if number % 1000 == 0 { a += line(number, "inserted in a") }
      if number % 1500 != 0 {
        b += line(number, number % 89 == 0 ? "changed in b" : "")
      }
    }
    return (Data(base.utf8), Data(a.utf8), Data(b.utf8))
  }

  @Test func threeFilesOfAHundredThousandLinesMakeASession() async throws {
    let inputs = Self.inputs()

    let clock = ContinuousClock()
    let start = clock.now
    let session = try await Session.merge(
      base: SourceFile(bytes: inputs.base, label: "base"),
      a: SourceFile(bytes: inputs.a, label: "a"),
      b: SourceFile(bytes: inputs.b, label: "b"))
    let duration = clock.now - start

    let layout = session.rowLayout
    #expect(layout.lineCount(in: .base) == Self.lineCount)
    #expect(session.blocks.contains { $0.kind == .conflict })
    for role in session.inputs.roles {
      let text = try #require(layout.displayText(for: role))
      #expect(text.rowCount == layout.rowCount)
      for line in stride(from: 0, to: layout.lineCount(in: role), by: 997) {
        #expect(layout.line(atRow: layout.row(ofLine: line, in: role), in: role) == line)
      }
    }
    #if DEBUG
      _ = duration
    #else
      // Only an optimized build is fast enough to open such a merge without waiting.
      #expect(duration < .seconds(2), "Opening took \(duration)")
    #endif
  }
}
