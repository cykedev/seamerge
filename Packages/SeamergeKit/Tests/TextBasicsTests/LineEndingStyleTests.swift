import Testing
import TextBasics

struct LineEndingStyleTests {
  @Test func countsWithOneKindOfLineEndingAreUniform() {
    #expect(LineEndingStyle(LineEndingCounts(cr: 2)) == .uniform(.cr))
  }

  @Test func countsWithSeveralKindsAreMixed() {
    let counts = LineEndingCounts(lf: 1, crlf: 3)

    #expect(LineEndingStyle(counts) == .mixed(counts))
    #expect(LineEndingStyle(counts)?.predominantLineEnding == .crlf)
  }

  @Test func onlyAUniformStyleHasAUniformLineEnding() {
    #expect(LineEndingStyle.uniform(.crlf).uniformLineEnding == .crlf)
    #expect(!LineEndingStyle.uniform(.crlf).isMixed)
    #expect(LineEndingStyle.mixed(LineEndingCounts(lf: 1, cr: 1)).uniformLineEnding == nil)
    #expect(LineEndingStyle.mixed(LineEndingCounts(lf: 1, cr: 1)).isMixed)
  }

  @Test func countsWithoutLineEndingsHaveNoStyle() {
    #expect(LineEndingStyle(LineEndingCounts()) == nil)
  }

  @Test func majorityGoesToTheMostFrequentLineEndingAndTiesToTheFirstCase() {
    #expect(LineEndingCounts().majority == nil)
    #expect(LineEndingCounts(lf: 1, cr: 3).majority == .cr)
    #expect(LineEndingCounts(lf: 2, crlf: 2, cr: 1).majority == .lf)
    #expect(LineEndingCounts(lf: 2, crlf: 3, cr: 3).total == 8)
  }
}
