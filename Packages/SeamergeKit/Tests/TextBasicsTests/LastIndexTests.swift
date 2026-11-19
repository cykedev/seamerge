import Testing
import TextBasics

struct LastIndexTests {
  @Test func findsTheLastIndexOfThePrefixForEverySplit() {
    for count in 1...9 {
      for split in 1...count {
        #expect((0..<count).lastIndex(holding: { $0 < split }) == split - 1, "\(count), \(split)")
      }
    }
  }

  @Test func firstIndexCountsEvenWhereItFails() {
    #expect((3..<8).lastIndex(holding: { _ in false }) == 3)
    #expect((3..<4).lastIndex(holding: { _ in false }) == 3)
  }

  @Test func emptyRangeAnswersItsLowerBound() {
    #expect((0..<0).lastIndex(holding: { _ in true }) == 0)
    #expect((5..<5).lastIndex(holding: { _ in true }) == 5)
  }
}
