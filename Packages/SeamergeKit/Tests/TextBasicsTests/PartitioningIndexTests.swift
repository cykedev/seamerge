import Testing
import TextBasics

struct PartitioningIndexTests {
  @Test func findsTheFirstElementOfTheSuffixForEverySplit() {
    for count in 0...9 {
      for split in 0...count {
        let elements = (0..<count).map { $0 >= split }
        #expect(elements.partitioningIndex { $0 } == split, "count \(count), split \(split)")
      }
    }
  }

  @Test func answersInTheIndicesOfASlice() {
    let slice = [1, 2, 3, 4, 5, 6, 7][2..<6]

    #expect(slice.partitioningIndex { $0 > 4 } == 4)
    #expect(slice.partitioningIndex { $0 > 9 } == slice.endIndex)
    #expect(slice.partitioningIndex { $0 > 0 } == slice.startIndex)
  }

  @Test func searchesARangeOfIndices() {
    let squares = [0, 1, 4, 9, 16, 25]

    #expect((0..<squares.count).partitioningIndex { squares[$0] >= 10 } == 4)
  }
}
