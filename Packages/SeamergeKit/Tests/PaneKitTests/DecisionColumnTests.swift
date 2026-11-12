import AppKit
import Testing

@testable import PaneKit

/// Checks the decision column: its width, the signs of the blocks, the toggles at the current
/// block and under the resting pointer, and what they tell the delegate and VoiceOver.
@MainActor
@Suite struct DecisionColumnTests {
  @Test func columnTakesTheWidthOfItsWidestRowOfControlsBesideTheText() throws {
    let (pane, column, window, _) = Self.resultPane()
    defer { window.close() }
    let width = DecisionColumnView.width
    let cases: [[DecisionToggle]] = [
      [[.a], [.base], [.b]].map { SampleResult.toggle($0, isOn: false) },
      [
        DecisionToggle(roles: [.a], isOn: false, isDeletion: true, help: ""),
        SampleResult.toggle([.base, .b], isOn: true),
      ],
    ]
    for toggles in cases {
      let row =
        toggles.map(DecisionToggleButton.width(of:)).reduce(0, +)
        + CGFloat(toggles.count) * Theme.decisionControlSpacing + Theme.decisionControlSize
        + 2 * Theme.decisionColumnInset
      #expect(row <= width)
    }
    #expect(width.truncatingRemainder(dividingBy: 4) == 0)
    #expect(column.frame.width == width)
    let bar = try #require(pane.overviewBar)
    #expect(column.frame.maxX == bar.frame.minX)
    let scrollView = try #require(pane.documentView.enclosingScrollView)
    #expect(scrollView.frame.maxX == column.frame.minX)
    #expect(pane.minimumWidth >= width + Theme.overviewBarWidth)
  }

  @Test func everyBlockWithAStateShowsItsSignAtItsFirstRow() throws {
    let (pane, column, window, _) = Self.resultPane()
    defer { window.close() }
    pane.currentBlock = nil
    let signs = try #require(column.accessibilityChildren() as? [NSAccessibilityElement])
    let described = signs.map {
      "\($0.accessibilityLabel() ?? ""), \($0.accessibilityValue() as? String ?? "")"
    }
    #expect(
      described == [
        "Taken automatically: A, Line 3", "Taken automatically: B, Line 5",
        "Nothing taken, After line 7", "Taken automatically: A, B, Line 11",
        "Chosen: A, Line 13", "Chosen: B, Line 15", "Chosen: Base, Line 17",
        "Chosen: A, B, Line 19",
        "Chosen: B, A, Line 21", "Edited by hand, Line 23", "Open conflict, Line 25",
      ])
    let rowHeight = pane.theme.rowHeight
    let firstRows = pane.content.blocks.map(\.rows.lowerBound)
    for (sign, row) in zip(signs, firstRows) where sign.accessibilityLabel() != "Nothing taken" {
      #expect(sign.accessibilityFrameInParentSpace().midY == (CGFloat(row) + 0.5) * rowHeight)
    }
    #expect(column.subviews.isEmpty)
  }

  @Test func currentBlockShowsItsTogglesForVoiceOverAndTheKeyboard() throws {
    let (pane, column, window, _) = Self.resultPane()
    defer { window.close() }
    pane.currentBlock = SampleResult.Block.open.rawValue
    let toggles = Self.controls(of: column).compactMap { $0 as? DecisionToggleButton }
    #expect(toggles.map { $0.accessibilityLabel() } == ["A", "Base", "B"])
    #expect(toggles.allSatisfy { $0.accessibilityRole() == .checkBox })
    #expect(toggles.allSatisfy { $0.accessibilitySubrole() == .toggle })
    #expect(toggles.map { $0.accessibilityValue() as? NSNumber } == [0, 0, 0])
    #expect(toggles[0].accessibilityHelp() == "Take the version of feature/login.")
    #expect(toggles[0].toolTip == "Take the version of feature/login.")
    #expect(!Self.controls(of: column).contains { $0 is ResetBlockButton })
    let rowHeight = pane.theme.rowHeight
    let firstRow = CGFloat(pane.content.blocks[SampleResult.Block.open.rawValue].rows.lowerBound)
    for toggle in toggles {
      #expect(
        column.convert(toggle.frame, from: toggle.superview).midY == (firstRow + 0.5) * rowHeight)
      #expect(toggle.frame.width >= 20 && toggle.frame.height >= 20)
    }
    let children = try #require(column.accessibilityChildren())
    let group = try #require(children.last as? NSView)
    #expect(group.accessibilityRole() == .group)
    #expect(group.accessibilityLabel() == "Open conflict, Line 25")
    #expect(group.accessibilityChildren()?.first as? NSView === toggles[0])
  }

  @Test func voiceOverFindsTheTogglesOfABlockWhereItsSignWouldBe() throws {
    let (pane, column, window, _) = Self.resultPane()
    defer { window.close() }
    pane.currentBlock = SampleResult.Block.chosenA.rawValue
    let children = try #require(column.accessibilityChildren())
    let names = children.map {
      ($0 as? NSAccessibilityElement)?.accessibilityValue() as? String ?? ($0 as? NSView)?
        .accessibilityLabel() ?? ""
    }
    #expect(
      names == [
        "Line 3", "Line 5", "After line 7", "Line 11", "Chosen: A, Line 13", "Line 15", "Line 17",
        "Line 19", "Line 21", "Line 23", "Line 25",
      ])
    // The elements of the signs stay the same between questions, for VoiceOver's cursor.
    let again = try #require(column.accessibilityChildren())
    #expect((children[0] as AnyObject) === (again[0] as AnyObject))
    // The pointer resting on another block makes a second group that names its own block.
    let row = pane.content.blocks[SampleResult.Block.chosenB.rawValue].rows.lowerBound
    column.pointerMoved(to: CGPoint(x: 10, y: (CGFloat(row) + 0.5) * pane.theme.rowHeight))
    try #require(column.hoverTimer).fire()
    let groups = try #require(column.accessibilityChildren()).compactMap {
      ($0 as? DecisionControlGroup)?.accessibilityLabel()
    }
    #expect(groups == ["Chosen: A, Line 13", "Chosen: B, Line 15"])
  }

  @Test func pointerOnABlockWithoutRowsShowsItsToggles() throws {
    let (pane, column, window, _) = Self.resultPane()
    defer { window.close() }
    let block = SampleResult.Block.nothingTaken.rawValue
    let boundary = CGFloat(pane.content.blocks[block].rows.lowerBound) * pane.theme.rowHeight
    column.pointerMoved(to: CGPoint(x: 10, y: boundary + 3))
    try #require(column.hoverTimer).fire()
    #expect(Self.controls(of: column).contains { $0.block == block })
  }

  @Test func togglesOfABlockWithSharedInputsNameThemAll() throws {
    let (pane, column, window, _) = Self.resultPane()
    defer { window.close() }
    pane.currentBlock = SampleResult.Block.nothingTaken.rawValue
    let toggles = Self.controls(of: column).compactMap { $0 as? DecisionToggleButton }
    #expect(toggles.map { $0.accessibilityLabel() } == ["Base and A", "B, deletion"])
    #expect(toggles.map { DecisionToggleButton.label(of: $0.toggle) } == ["Base · A", "B"])
    #expect(toggles.map { $0.accessibilityValue() as? NSNumber } == [0, 1])
    let reset = try #require(Self.controls(of: column).compactMap { $0 as? ResetBlockButton }.first)
    #expect(reset.accessibilityLabel() == "Reset Block")
    #expect(reset.frame.minX > toggles[1].frame.maxX)
  }

  @Test func pressingAToggleOrTheArrowTellsTheDelegateAndChangesNothingOnItsOwn() throws {
    let (pane, column, window, recorder) = Self.resultPane()
    defer { window.close() }
    let block = SampleResult.Block.chosenA.rawValue
    pane.currentBlock = block
    let toggles = Self.controls(of: column).compactMap { $0 as? DecisionToggleButton }
    toggles[2].performClick(nil)
    #expect(toggles[2].accessibilityPerformPress())
    let reset = try #require(Self.controls(of: column).compactMap { $0 as? ResetBlockButton }.first)
    reset.performClick(nil)
    #expect(
      recorder.switched == [Switch(toggle: 2, block: block), Switch(toggle: 2, block: block)])
    #expect(recorder.resets == [block])
    #expect(toggles[2].accessibilityValue() as? NSNumber == 0)
    // The owner answers with the new decision; the same buttons show it, and the focus stays.
    window.makeFirstResponder(toggles[2])
    var decision = try #require(column.decisions[block])
    decision.state = .chosen([.a, .b])
    decision.toggles[2].isOn = true
    column.decisions[block] = decision
    let shown = Self.controls(of: column).compactMap { $0 as? DecisionToggleButton }
    #expect(shown.map(ObjectIdentifier.init) == toggles.map(ObjectIdentifier.init))
    #expect(shown[2].accessibilityValue() as? NSNumber == 1)
    #expect(window.firstResponder === shown[2])
  }

  @Test func clickBesideABlockNamesItAndClickBesideUnchangedRowsNamesNone() throws {
    let (pane, column, window, recorder) = Self.resultPane()
    defer { window.close() }
    let block = SampleResult.Block.chosenB.rawValue
    let rowHeight = pane.theme.rowHeight
    let row = try #require(pane.content.blocks[block].rows.first)
    try Clicking.click(column, at: CGPoint(x: 4, y: (CGFloat(row) + 0.5) * rowHeight))
    try Clicking.click(column, at: CGPoint(x: 4, y: 0.5 * rowHeight))
    #expect(pane.content.blockIndex(atRow: 0) == nil)
    #expect(recorder.clicked == [block])
  }

  @Test func pointerShowsTheTogglesOfABlockOnlyOnceItRests() throws {
    let (pane, column, window, _) = Self.resultPane()
    defer { window.close() }
    pane.currentBlock = SampleResult.Block.open.rawValue
    let rowHeight = pane.theme.rowHeight
    func center(of block: SampleResult.Block) -> CGPoint {
      CGPoint(
        x: 10, y: (CGFloat(pane.content.blocks[block.rawValue].rows.lowerBound) + 0.5) * rowHeight)
    }
    func blocksWithToggles() -> Set<Int> {
      Set(Self.controls(of: column).compactMap { ($0 as? DecisionToggleButton)?.block })
    }
    column.pointerMoved(to: center(of: .chosenB))
    #expect(blocksWithToggles() == [SampleResult.Block.open.rawValue])
    let timer = try #require(column.hoverTimer)
    #expect((0.05...0.1).contains(timer.fireDate.timeIntervalSinceNow))
    // Moving on within the time starts it anew.
    column.pointerMoved(to: center(of: .chosenBase))
    #expect(!timer.isValid)
    try #require(column.hoverTimer).fire()
    #expect(
      blocksWithToggles() == [
        SampleResult.Block.open.rawValue, SampleResult.Block.chosenBase.rawValue,
      ])
    // Leaving the block takes its toggles away at once.
    column.pointerMoved(to: center(of: .automaticA))
    #expect(blocksWithToggles() == [SampleResult.Block.open.rawValue])
    column.pointerLeft()
    #expect(column.hoverTimer == nil)
    #expect(blocksWithToggles() == [SampleResult.Block.open.rawValue])
  }

  @Test func togglesStayLargeEnoughToClickWhenRowsAreLow() throws {
    let theme = Theme(font: .monospacedSystemFont(ofSize: 10, weight: .regular))
    let (pane, column, window, _) = Self.resultPane(theme: theme)
    defer { window.close() }
    #expect(theme.rowHeight < 20)
    pane.currentBlock = SampleResult.Block.chosenBThenA.rawValue
    let controls = Self.controls(of: column)
    #expect(controls.count == 4)
    for control in controls {
      #expect(control.frame.width >= 20 && control.frame.height >= 20)
    }
  }

  @Test func blockBehindACollapsedRunShowsNoSign() throws {
    let (pane, column, window, _) = Self.resultPane()
    defer { window.close() }
    pane.currentBlock = nil
    pane.collapsedRuns = [CollapsedRun(rows: 3..<6)]
    let signs = try #require(column.accessibilityChildren() as? [NSAccessibilityElement])
    #expect(signs.count == 10)
    #expect(signs.first?.accessibilityValue() as? String == "Line 3")
  }

  @Test func pointerOnARowOfABlockBesideABlockWithoutRowsShowsTheTogglesOfItsOwnBlock() throws {
    let pane = PaneView()
    pane.content = PaneContent(
      text: "zero\none\ntwo\nthree\nfour", lineNumbers: [0, 1, 2, 3, 4],
      blocks: [
        PaneBlock(rows: 1..<2, style: .tinted(.a)), PaneBlock(rows: 2..<2, style: .unchanged),
      ])
    let column = DecisionColumnView()
    let toggles = [SampleResult.toggle([.a], isOn: true), SampleResult.toggle([.b], isOn: false)]
    column.decisions = [
      0: BlockDecision(state: .automatic([.a]), toggles: toggles),
      1: BlockDecision(state: .chosen([]), toggles: toggles, canReset: true),
    ]
    pane.decisionColumn = column
    let window = Rendering.host(pane, size: CGSize(width: 400, height: 200))
    defer { window.close() }
    let boundary = 2 * pane.theme.rowHeight
    func blockUnderThePointer(at y: CGFloat) throws -> Set<Int> {
      column.pointerLeft()
      column.pointerMoved(to: CGPoint(x: 10, y: y))
      try #require(column.hoverTimer).fire()
      return Set(Self.controls(of: column).map(\.block))
    }
    // The last row of block 0 reaches down to the boundary of the empty block 1.
    #expect(try blockUnderThePointer(at: boundary - 4) == [0])
    // The unchanged row below the boundary belongs to no block, so the empty block takes it.
    #expect(try blockUnderThePointer(at: boundary + 4) == [1])
  }

  @Test func signsOfBlocksAtTheSamePlaceMoveApartAndEachFindsItsBlock() throws {
    // Block 1 lies on the boundary below block 0, block 3 on the boundary above block 4: each
    // pair asks for places half a row apart, closer than a click's room.
    let pane = PaneView()
    pane.content = PaneContent(
      text: "zero\none\ntwo\nthree\nfour\nfive\nsix", lineNumbers: [0, 1, 2, 3, 4, 5, 6],
      blocks: [
        PaneBlock(rows: 1..<2, style: .tinted(.a)), PaneBlock(rows: 2..<2, style: .unchanged),
        PaneBlock(rows: 2..<4, style: .unchanged), PaneBlock(rows: 4..<4, style: .unchanged),
        PaneBlock(rows: 4..<5, style: .tinted(.b)),
      ])
    let column = DecisionColumnView()
    let toggles = [SampleResult.toggle([.a], isOn: true), SampleResult.toggle([.b], isOn: true)]
    column.decisions = [
      0: BlockDecision(state: .automatic([.a, .b]), toggles: toggles),
      1: BlockDecision(state: .automatic([.a, .b]), toggles: toggles),
      3: BlockDecision(state: .chosen([]), toggles: toggles),
      4: BlockDecision(state: .automatic([.b]), toggles: toggles),
    ]
    let recorder = DecisionRecorder()
    column.delegate = recorder
    pane.decisionColumn = column
    let window = Rendering.host(pane, size: CGSize(width: 400, height: 200), isKey: true)
    defer { window.close() }
    let rowHeight = pane.theme.rowHeight
    let signs = try #require(column.accessibilityChildren() as? [NSAccessibilityElement])
    #expect(signs.count == 4)
    let frames = signs.map { $0.accessibilityFrameInParentSpace() }
    let middles = frames.map(\.midY)
    for (upper, lower) in zip(middles, middles.dropFirst()) {
      #expect(lower - upper >= Theme.decisionControlSize)
    }
    for (upper, lower) in zip(frames, frames.dropFirst()) {
      #expect(!upper.intersects(lower))
    }
    // The signs of blocks with rows stay beside their first rows; those on boundaries give way.
    #expect(middles[0] == 1.5 * rowHeight)
    #expect(middles[3] == 4.5 * rowHeight)
    for (block, middle) in zip([0, 1, 3, 4], middles) {
      for offset in [-(Theme.decisionControlSize / 2 - 1), 0, Theme.decisionControlSize / 2 - 1] {
        column.pointerLeft()
        column.pointerMoved(to: CGPoint(x: 10, y: middle + offset))
        try #require(column.hoverTimer).fire()
        let shown = Set(Self.controls(of: column).map(\.block))
        #expect(shown == [block], "pointer at \(middle + offset)")
        for control in Self.controls(of: column) {
          #expect(control.frame.width >= 20 && control.frame.height >= 20)
        }
      }
      column.pointerLeft()
      try Clicking.click(column, at: CGPoint(x: 6, y: middle))
    }
    #expect(recorder.clicked == [0, 1, 3, 4])
  }

  @Test func signsAtTheStartAndTheEndOfTheTextGiveWayInwards() throws {
    // A deletion before the first line and one after the last, beside blocks of one row there.
    let rowCount = 10
    let pane = PaneView()
    pane.content = PaneContent(
      text: (0..<rowCount).map { "line \($0)" }.joined(separator: "\n"),
      lineNumbers: (0..<rowCount).map(Int32.init),
      blocks: [
        PaneBlock(rows: 0..<0, style: .unchanged), PaneBlock(rows: 0..<1, style: .tinted(.a)),
        PaneBlock(rows: 9..<10, style: .tinted(.b)), PaneBlock(rows: 10..<10, style: .unchanged),
      ])
    let column = DecisionColumnView()
    let toggles = [SampleResult.toggle([.a], isOn: true), SampleResult.toggle([.b], isOn: true)]
    column.decisions = Dictionary(
      uniqueKeysWithValues: (0..<4).map {
        ($0, BlockDecision(state: .automatic([.a, .b]), toggles: toggles))
      })
    pane.decisionColumn = column
    let window = Rendering.host(pane, size: CGSize(width: 400, height: 400), isKey: true)
    defer { window.close() }
    let rows = 0...CGFloat(rowCount) * pane.theme.rowHeight
    let signs = try #require(column.accessibilityChildren() as? [NSAccessibilityElement])
    try #require(signs.count == 4)
    let middles = signs.map { $0.accessibilityFrameInParentSpace().midY }
    for middle in middles {
      let target =
        (middle - Theme.decisionControlSize / 2)...(middle + Theme.decisionControlSize / 2)
      #expect(rows.contains(target.lowerBound) && rows.contains(target.upperBound), "\(middle)")
    }
    for (upper, lower) in zip(middles, middles.dropFirst()) {
      #expect(lower - upper >= Theme.decisionControlSize)
    }
    for (block, middle) in zip(0..<4, middles) {
      column.pointerLeft()
      column.pointerMoved(to: CGPoint(x: 10, y: middle))
      try #require(column.hoverTimer).fire()
      #expect(Set(Self.controls(of: column).map(\.block)) == [block])
    }
  }

  @Test func signsOfAChainStayInPlaceOnTheTextWhileThePaneScrolls() throws {
    // Blocks of one row, each with a deletion after it: two signs a row, which push each other
    // far down.
    let rowCount = 100
    var blocks: [PaneBlock] = []
    for row in 40..<52 {
      blocks.append(PaneBlock(rows: row..<row + 1, style: .tinted(.a)))
      blocks.append(PaneBlock(rows: row + 1..<row + 1, style: .unchanged))
    }
    let pane = PaneView()
    pane.content = PaneContent(
      text: (0..<rowCount).map { "line \($0)" }.joined(separator: "\n"),
      lineNumbers: (0..<rowCount).map(Int32.init), blocks: blocks)
    let column = DecisionColumnView()
    let toggles = [SampleResult.toggle([.a], isOn: true), SampleResult.toggle([.b], isOn: true)]
    column.decisions = Dictionary(
      uniqueKeysWithValues: blocks.indices.map {
        ($0, BlockDecision(state: .automatic([.a]), toggles: toggles))
      })
    pane.decisionColumn = column
    let window = Rendering.host(pane, size: CGSize(width: 400, height: 160), isKey: true)
    defer { window.close() }
    let rowHeight = pane.theme.rowHeight
    func placesOnTheText(scrolledTo row: Int) throws -> [String: CGFloat] {
      pane.scroll(to: CGPoint(x: 0, y: CGFloat(row) * rowHeight))
      let offset = pane.scrollOrigin.y
      let signs = try #require(column.accessibilityChildren() as? [NSAccessibilityElement])
      return Dictionary(
        uniqueKeysWithValues: signs.map {
          (
            $0.accessibilityValue() as? String ?? "",
            $0.accessibilityFrameInParentSpace().midY + offset
          )
        })
    }
    let early = try placesOnTheText(scrolledTo: 44)
    let late = try placesOnTheText(scrolledTo: 50)
    let shared = Set(early.keys).intersection(late.keys)
    try #require(shared.count > 1, "\(early.keys.sorted()) \(late.keys.sorted())")
    for key in shared {
      #expect(early[key] == late[key], "\(key)")
    }
  }

  /// The toggles and reset arrows that `column` shows.
  static func controls(of column: DecisionColumnView) -> [DecisionControl] {
    column.subviews.flatMap { ($0 as? DecisionControlGroup)?.controls ?? [] }
  }

  /// The result pane of the sample with its decision column and overview bar, in a key window,
  /// with the delegate that records what the column reports.
  static func resultPane(
    theme: Theme = Theme(), size: CGSize = CGSize(width: 900, height: 640),
    appearance: NSAppearance? = nil
  ) -> (PaneView, DecisionColumnView, NSWindow, DecisionRecorder) {
    let pane = PaneView(theme: theme)
    let (content, decisions) = SampleResult.transcoder.content()
    pane.content = content
    let column = DecisionColumnView()
    column.theme = theme
    column.decisions = decisions
    let recorder = DecisionRecorder()
    column.delegate = recorder
    pane.decisionColumn = column
    let bar = OverviewBar()
    bar.theme = theme
    pane.overviewBar = bar
    let window = Rendering.host(pane, size: size, appearance: appearance, isKey: true)
    pane.currentBlock = SampleResult.Block.open.rawValue
    return (pane, column, window, recorder)
  }
}

/// A toggle that the user switched.
struct Switch: Equatable {
  var toggle: Int
  var block: Int
}

/// Records what a decision column reports.
@MainActor
final class DecisionRecorder: DecisionColumnDelegate {
  private(set) var switched: [Switch] = []
  private(set) var resets: [Int] = []
  private(set) var clicked: [Int] = []

  func decisionColumn(
    _ column: DecisionColumnView, didSwitchToggle toggle: Int, ofBlock block: Int
  ) {
    switched.append(Switch(toggle: toggle, block: block))
  }

  func decisionColumn(_ column: DecisionColumnView, didAskToResetBlock block: Int) {
    resets.append(block)
  }

  func decisionColumn(_ column: DecisionColumnView, didClickBlock block: Int) {
    clicked.append(block)
  }
}
