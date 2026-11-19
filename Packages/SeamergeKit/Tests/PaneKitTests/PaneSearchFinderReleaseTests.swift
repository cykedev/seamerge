import AppKit
import Synchronization
import Testing

@testable import PaneKit

/// The search text once the find bar closes: the search lets go of it, a copy of all the text it
/// goes through, and takes it anew as the find bar opens again.
///
/// These tests belong to the tests of the finder, which run one after the other: the find
/// pasteboard that they all use is one for the whole system.
extension PaneSearchFinderTests {
  @Test func closedFindBarHoldsNoSearchTextAndFindsAgainOnceItOpens() async throws {
    try await FindPasteboard.preserving {
      let panes = SearchPanes()
      defer { panes.window.close() }
      panes.search.perform(.showFindInterface)
      try enter("needle", into: findField(of: panes.search), in: panes.window)
      await panes.observer.waitForMatches { panes.search.matches.count == 7 }
      #expect(panes.search.snapshot.withLock(\.length) == 74)

      panes.search.perform(.hideFindInterface)
      #expect(panes.search.snapshot.withLock(\.length) == 0)

      // The find bar opens with the search text of the find pasteboard and searches for it at
      // once; typing before that search ends would race with it.
      panes.search.perform(.showFindInterface)
      await panes.observer.waitForMatches { panes.search.matches.count == 7 }
      #expect(panes.search.snapshot.withLock(\.length) == 74)
      try enter("needle tail", into: findField(of: panes.search), in: panes.window)
      await panes.observer.waitForMatches { panes.search.matches.count == 1 }
      #expect(
        panes.search.matches.map { "\(panes.name(of: $0.pane)) \($0.range)" } == ["A 21..<32"])
    }
  }
}
