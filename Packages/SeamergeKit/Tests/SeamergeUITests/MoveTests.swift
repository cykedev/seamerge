import AppKit
import MergeModel
import Testing

@testable import PaneKit
@testable import SeamergeUI

/// Moved lines in the window: the arrows in the gutters of the sides that moved them, which way
/// they point before and after Swap Sides, what they say, the jump to the other end by a click
/// and by Go to Other End of Move, and how the ends count.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct MoveTests {
  @Test func arrowsOfAFunctionMovedDownPointToEachOther() async throws {
    let controller = try Windows.controller(for: try await MoveSamples.movedDown())
    let (a, b) = try Self.panes(of: controller)
    let (source, destination) = try Self.ends(in: a, b)
    #expect(source < destination)

    let sourceMark = try #require(a.content.blocks[source].move)
    #expect(sourceMark.end == .source)
    #expect(sourceMark.otherBlock == destination)
    #expect(sourceMark.otherLine == MoveSamples.movedDownDestinationLine)
    #expect(b.content.blocks[source].move == nil)

    let destinationMark = try #require(b.content.blocks[destination].move)
    #expect(destinationMark.end == .destination)
    #expect(destinationMark.otherBlock == source)
    #expect(destinationMark.otherLine == MoveSamples.movedDownSourceLine)
    #expect(a.content.blocks[destination].move == nil)

    #expect(try Self.arrowLabels(of: a) == ["Moved to line 15"])
    #expect(try Self.arrowLabels(of: b) == ["Moved here from line 3"])
  }

  @Test func arrowsOfAFunctionMovedUpPointToEachOther() async throws {
    let controller = try Windows.controller(for: try await MoveSamples.movedUp())
    let (a, b) = try Self.panes(of: controller)
    let (source, destination) = try Self.ends(in: a, b)
    #expect(destination < source)
    #expect(try Self.arrowLabels(of: a) == ["Moved to line 3"])
    #expect(try Self.arrowLabels(of: b) == ["Moved here from line 15"])
  }

  @Test func swapSidesTurnsTheWordsAroundAndKeepsTheArrowsPointingAtTheOtherEnd() async throws {
    let controller = try Windows.controller(for: try await MoveSamples.movedDown())
    let (a, b) = try Self.panes(of: controller)
    let (source, destination) = try Self.ends(in: a, b)
    #expect(try Self.arrowPointsDown(atBlock: source, of: a))
    #expect(try !Self.arrowPointsDown(atBlock: destination, of: b))
    let textOfB = b.content.text
    controller.swapSides(nil)
    let (left, right) = try Self.panes(of: controller)
    // B is on the left now; its lines leave and arrive in A.
    #expect(left.content.text == textOfB)
    let leaving = try #require(left.content.blocks[destination].move)
    #expect(leaving.end == .source)
    #expect(leaving.otherBlock == source)
    let arriving = try #require(right.content.blocks[source].move)
    #expect(arriving.end == .destination)
    #expect(arriving.otherBlock == destination)
    #expect(try Self.arrowLabels(of: left) == ["Moved to line 3"])
    #expect(try Self.arrowLabels(of: right) == ["Moved here from line 15"])
    // The lines of B on the left arrived above the place they left in A on the right.
    #expect(try !Self.arrowPointsDown(atBlock: destination, of: left))
    #expect(try Self.arrowPointsDown(atBlock: source, of: right))
  }

  @Test func goToOtherEndOfMoveIsValidOnlyAtAnEndOfAMove() async throws {
    let controller = try Windows.controller(for: try await MoveSamples.movedDown())
    let (a, b) = try Self.panes(of: controller)
    let (source, destination) = try Self.ends(in: a, b)
    let other = try #require(
      a.content.blocks.indices.first { $0 != source && $0 != destination })
    controller.presentation.setCurrentBlock(other)
    #expect(!controller.canPerform(.goToOtherEndOfMove))
    controller.presentation.setCurrentBlock(nil)
    #expect(!controller.canPerform(.goToOtherEndOfMove))
    for end in [source, destination] {
      controller.presentation.setCurrentBlock(end)
      #expect(controller.canPerform(.goToOtherEndOfMove))
    }
    let comparison = try Windows.controller(for: try await SampleDiffs.greeting())
    #expect(!comparison.canPerform(.goToOtherEndOfMove))
  }

  @Test func goToOtherEndOfMoveMakesTheOtherEndCurrentAndBringsItIntoView() async throws {
    let controller = try Windows.controller(for: try await MoveSamples.movedFarDown())
    let (a, b) = try Self.panes(of: controller)
    let (source, destination) = try Self.ends(in: a, b)
    #expect(!b.showsWhole(rows: b.content.blocks[destination].rows.prefix(1)))
    controller.presentation.setCurrentBlock(source)

    controller.perform(.goToOtherEndOfMove)
    #expect(controller.presentation.currentBlock == destination)
    #expect(b.showsWhole(rows: b.content.blocks[destination].rows.prefix(1)))

    controller.perform(.goToOtherEndOfMove)
    #expect(controller.presentation.currentBlock == source)
    #expect(a.showsWhole(rows: a.content.blocks[source].rows.prefix(1)))
  }

  @Test func clickOnAnArrowGoesToTheOtherEnd() async throws {
    let controller = try Windows.controller(for: try await MoveSamples.movedFarDown())
    let (a, b) = try Self.panes(of: controller)
    let (source, destination) = try Self.ends(in: a, b)
    controller.presentation.setCurrentBlock(source)
    let row = a.content.blocks[source].rows.lowerBound
    a.delegate?.pane(a, didClick: PaneHit(row: row, block: source, isOnMoveArrow: true))
    #expect(controller.presentation.currentBlock == destination)
    #expect(b.showsWhole(rows: b.content.blocks[destination].rows.prefix(1)))

    // VoiceOver presses the same arrow.
    let button = try #require(try Self.arrowButtons(of: b).first)
    #expect(button.accessibilityPerformPress())
    #expect(controller.presentation.currentBlock == source)
  }

  @Test func eachEndCountsAsAChange() async throws {
    let session = try await MoveSamples.movedDown()
    let controller = try Windows.controller(for: session)
    let (a, b) = try Self.panes(of: controller)
    let (source, destination) = try Self.ends(in: a, b)
    let count = controller.presentation.changes.blocks.count
    #expect(count == 3)
    for end in [source, destination] {
      controller.presentation.jump(to: end)
      #expect(Self.countLabel(of: controller) == "Change \(end + 1) of \(count)")
    }
  }

  @Test func connectedSidesShowTheArrowsWithoutABandBetweenTheEnds() async throws {
    let controller = try Windows.controller(for: try await MoveSamples.movedDown())
    controller.showConnectedSides(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let (a, b) = try Self.panes(of: controller)
    let (source, destination) = try Self.ends(in: a, b)
    #expect(try Self.arrowLabels(of: a) == ["Moved to line 15"])
    #expect(try Self.arrowLabels(of: b) == ["Moved here from line 3"])
    let bands = try #require(controller.layout.seams.first?.bands)
    // Each end has its own band, which narrows to the place where the other side lacks the
    // lines; none runs from one end to the other.
    let sourceBand = try #require(bands.first { $0.block == source })
    #expect(sourceBand.right.lowerBound == sourceBand.right.upperBound)
    let destinationBand = try #require(bands.first { $0.block == destination })
    #expect(destinationBand.left.lowerBound == destinationBand.left.upperBound)
    #expect(Set(bands.map(\.block)).count == bands.count)
  }

  @Test func mergeShowsTheArrowsOnlyInThePaneOfTheSideThatMovedTheLines() async throws {
    let controller = try Windows.controller(for: try await MoveSamples.movedInA())
    let layout = controller.layout
    let a = try #require(layout.sourcePane(.a))
    let base = try #require(layout.sourcePane(.base))
    let b = try #require(layout.sourcePane(.b))
    let result = try #require(layout.resultPane)
    #expect(a.content.blocks.compactMap(\.move).map(\.end) == [.source, .destination])
    for pane in [base, b, result] {
      #expect(pane.content.blocks.allSatisfy { $0.move == nil })
    }
    #expect(try Self.arrowLabels(of: a) == ["Moved to line 15", "Moved here from line 3"])
    #expect(try Self.arrowLabels(of: b).isEmpty)

    let source = try #require(a.content.blocks.firstIndex { $0.move?.end == .source })
    controller.presentation.setCurrentBlock(source)
    controller.perform(.goToOtherEndOfMove)
    #expect(controller.presentation.currentBlock == a.content.blocks[source].move?.otherBlock)
  }

  @Test func mergeOfBShowsTheArrowsInThePaneOfB() async throws {
    let controller = try Windows.controller(for: try await MoveSamples.movedInB())
    let a = try #require(controller.layout.sourcePane(.a))
    let b = try #require(controller.layout.sourcePane(.b))
    #expect(a.content.blocks.allSatisfy { $0.move == nil })
    #expect(b.content.blocks.compactMap(\.move).map(\.end) == [.source, .destination])
  }

  /// The panes of A and B, left and right.
  private static func panes(
    of controller: SessionWindowController
  ) throws -> (PaneView, PaneView) {
    let panes = controller.layout.sourcePanes.map(\.pane)
    try #require(panes.count == 2)
    return (panes[0], panes[1])
  }

  /// The blocks of both ends of the only move, the source on the left and the destination on
  /// the right.
  private static func ends(
    in left: PaneView, _ right: PaneView
  ) throws -> (source: Int, destination: Int) {
    let source = try #require(left.content.blocks.firstIndex { $0.move != nil })
    let destination = try #require(right.content.blocks.firstIndex { $0.move != nil })
    return (source, destination)
  }

  /// Whether the gutter of `pane` draws the arrow beside the block at `index` pointing down.
  private static func arrowPointsDown(atBlock index: Int, of pane: PaneView) throws -> Bool {
    let row = pane.content.blocks[index].rows.lowerBound
    guard
      case .move(_, let pointsDown, _) = try #require(pane.gutterView.marks(ofRow: row).first?.mark)
    else {
      Issue.record("The block \(index) has no arrow")
      return false
    }
    return pointsDown
  }

  /// The buttons of the arrows of moves that VoiceOver finds in the gutter of `pane`, in view.
  private static func arrowButtons(of pane: PaneView) throws -> [NSAccessibilityElement] {
    let gutter = try #require(pane.subviews.first { $0.accessibilityLabel() == "Change markers" })
    let elements = try #require(gutter.accessibilityChildren() as? [NSAccessibilityElement])
    return elements.filter {
      $0.accessibilityRole() == .button && $0.accessibilityLabel()?.hasPrefix("Moved") == true
    }
  }

  /// What VoiceOver calls the arrows of moves in the gutter of `pane`, after scrolling each end
  /// into view.
  private static func arrowLabels(of pane: PaneView) throws -> [String] {
    var labels: [String] = []
    for block in pane.content.blocks.indices where pane.content.blocks[block].move != nil {
      pane.reveal(block: block)
      let found = try arrowButtons(of: pane).compactMap { $0.accessibilityLabel() }
      labels.append(contentsOf: found.filter { !labels.contains($0) })
    }
    return labels
  }

  private static func countLabel(of controller: SessionWindowController) -> String? {
    controller.toolbar.toolbar.items.first { $0.itemIdentifier == .changeCount }?.view?
      .accessibilityLabel()
  }
}

/// Files in which a function moves, with unchanged lines around it and one other change.
enum MoveSamples {
  /// The function that moves, four lines with enough letters to count as a move.
  static let function = [
    "func greeting(for name: String) -> String {",
    "  let salutation = \"Hello\"",
    "  return salutation + \", \" + name",
    "}",
  ]

  /// Lines that stay, each different from the others.
  static func lines(_ range: Range<Int>) -> [String] {
    range.map { "let constant\($0) = \($0 * 7)" }
  }

  static func text(_ lines: [String]) -> String {
    lines.joined(separator: "\n") + "\n"
  }

  /// The zero-based line in the older file where the function stood.
  static let movedDownSourceLine = 2

  /// The zero-based line in the newer file where the function stands after moving down.
  static let movedDownDestinationLine = 14

  /// A comparison in which the function moves from line 3 down to line 15 and a line between
  /// changes.
  static func movedDown() async throws -> Session {
    let old = lines(0..<2) + function + lines(2..<14) + lines(100..<104)
    var new = lines(0..<2) + lines(2..<14) + function + lines(100..<104)
    new[8] += " // changed"
    return try await SampleDiffs.diff(old: text(old), new: text(new))
  }

  /// A comparison in which the function moves down past 300 lines, every seventh of which
  /// changes, so that no run of unchanged lines between the ends is long enough to collapse and
  /// the ends lie more than a window height apart.
  static func movedFarDown() async throws -> Session {
    let old = lines(0..<2) + function + lines(2..<302) + lines(400..<404)
    var new = lines(0..<2) + lines(2..<302) + function + lines(400..<404)
    for line in stride(from: 5, to: 302, by: 7) {
      new[line] += " // changed"
    }
    return try await SampleDiffs.diff(old: text(old), new: text(new))
  }

  /// The same comparison the other way round: the function moves up from line 15 to line 3.
  static func movedUp() async throws -> Session {
    let old = lines(0..<2) + lines(2..<14) + function + lines(100..<104)
    var new = lines(0..<2) + function + lines(2..<14) + lines(100..<104)
    new[2 + function.count + 6] += " // changed"
    return try await SampleDiffs.diff(old: text(old), new: text(new))
  }

  /// A merge in which A moves the function down and B changes a line far from it.
  static func movedInA() async throws -> Session {
    let base = lines(0..<2) + function + lines(2..<14) + lines(100..<104)
    let a = lines(0..<2) + lines(2..<14) + function + lines(100..<104)
    var b = base
    b[base.count - 1] += " // changed"
    return try await SampleMerges.merge(base: text(base), a: text(a), b: text(b))
  }

  /// A merge in which B moves the function down and A changes a line far from it.
  static func movedInB() async throws -> Session {
    let base = lines(0..<2) + function + lines(2..<14) + lines(100..<104)
    var a = base
    a[base.count - 1] += " // changed"
    let b = lines(0..<2) + lines(2..<14) + function + lines(100..<104)
    return try await SampleMerges.merge(base: text(base), a: text(a), b: text(b))
  }
}
