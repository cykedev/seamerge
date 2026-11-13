import AppKit
import Testing

@testable import PaneKit

/// Checks the decision column: its width, the rows of toggles at every block, what they tell the
/// delegate and VoiceOver, and that nothing in it changes under the pointer.
@MainActor
@Suite struct DecisionColumnTests {
  /// Where the parts of a row stand for the rows of the standard theme.
  static var layout: DecisionColumnLayout {
    DecisionColumnLayout(theme: Theme())
  }

  @Test func columnTakesTheWidthOfItsSlotsBesideTheText() throws {
    let (pane, column, window, _) = Self.resultPane()
    defer { window.close() }
    let width = column.width
    #expect(Self.layout.rowWidth + 2 * Theme.decisionColumnInset <= width)
    #expect(width.truncatingRemainder(dividingBy: 4) == 0)
    #expect(column.frame.width == width)
    let bar = try #require(pane.overviewBar)
    #expect(column.frame.maxX == bar.frame.minX)
    let scrollView = try #require(pane.documentView.enclosingScrollView)
    #expect(scrollView.frame.maxX == column.frame.minX)
    #expect(pane.minimumWidth >= width + Theme.overviewBarWidth)
  }

  @Test func everyBlockShowsItsTogglesAtItsFirstRowWhetherCurrentOrNot() throws {
    let (pane, column, window, _) = Self.resultPane()
    defer { window.close() }
    for current in [nil, SampleResult.Block.open.rawValue] {
      pane.currentBlock = current
      let rows = try #require(column.accessibilityChildren() as? [DecisionRow])
      #expect(
        rows.map(Self.spoken) == [
          "Taken automatically: A, Line 3", "Taken automatically: B, Line 5",
          "Nothing taken, After line 7", "Taken automatically: A, B, Line 11",
          "Chosen: A, Line 13", "Chosen: B, Line 15", "Chosen: Base, Line 17",
          "Chosen: A, B, Line 19", "Chosen: B, A, Line 21", "Edited by hand, Line 23",
          "Open conflict, Line 25",
        ])
      let rowHeight = pane.theme.rowHeight
      for row in rows where !pane.content.blocks[row.block].rows.isEmpty {
        let firstRow = CGFloat(pane.content.blocks[row.block].rows.lowerBound)
        #expect(abs(row.frame.midY - (firstRow + 0.5) * rowHeight) <= 0.5, "\(row.block)")
      }
    }
  }

  @Test func eachRowExplainsItsStateInAHelpTagAndToVoiceOver() throws {
    let (_, column, window, _) = Self.resultPane()
    defer { window.close() }
    let rows = column.rows
    for row in rows {
      #expect(row.accessibilityHelp() == row.toolTip)
      #expect((row.toolTip ?? "").count <= 75)
    }
    let helps = rows.compactMap(\.toolTip)
    #expect(helps.contains("Takes no lines, as you chose"))
    #expect(helps.contains("Holds lines that you typed or changed"))
    #expect(helps.contains("Takes the lines of A and B, as the merge decided"))
    #expect(helps.contains("Takes the lines of B and A, in the order you chose"))
    #expect(helps.last == "Differs on both sides; choose what the result takes")
  }

  @Test func cellsShowWhetherTheMergeOrTheUserTookAnInput() throws {
    let (_, column, window, _) = Self.resultPane()
    defer { window.close() }
    func faces(_ block: SampleResult.Block) -> [String] {
      Self.cells(of: Self.row(block, in: column)).map { "\(Self.name($0.role)) \($0.face)" }
    }
    #expect(faces(.automaticA) == ["A automatic", "Base off", "B off"])
    #expect(faces(.automaticBoth) == ["A automatic", "Base off", "B automatic"])
    #expect(faces(.chosenBThenA) == ["A chosen", "Base off", "B chosen"])
    #expect(faces(.edited) == ["A off", "Base off", "B off"])
    #expect(faces(.open) == ["A off", "Base off", "B off"])
    #expect(faces(.nothingTaken) == ["A off", "Base off", "B off"])
    // The warning sign stands only beside an open conflict, the arrow only where it can reset.
    let open = Self.row(.open, in: column)
    #expect(!open.controls.contains { $0 is ResetBlockButton })
    let nothing = Self.row(.nothingTaken, in: column)
    #expect(nothing.controls.contains { $0 is ResetBlockButton })
    #expect(!Self.row(.automaticA, in: column).controls.contains { $0 is ResetBlockButton })
  }

  @Test func movingThePointerOverTheColumnChangesNothing() throws {
    let (pane, column, window, _) = Self.resultPane()
    defer { window.close() }
    pane.currentBlock = nil
    let before = Self.snapshot(of: column)
    let height = column.bounds.height
    for type in [NSEvent.EventType.mouseEntered, .mouseMoved, .mouseExited] {
      for y in stride(from: 0, to: height, by: 3) {
        let point = column.convert(CGPoint(x: column.bounds.midX, y: y), to: nil)
        if type == .mouseMoved {
          let event = try #require(
            NSEvent.mouseEvent(
              with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0,
              pressure: 0))
          column.mouseMoved(with: event)
          window.contentView?.hitTest(point)?.mouseMoved(with: event)
        } else {
          let event = try #require(
            NSEvent.enterExitEvent(
              with: type, location: point, modifierFlags: [], timestamp: 0,
              windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0,
              userData: nil))
          column.mouseEntered(with: event)
          column.mouseExited(with: event)
        }
      }
    }
    #expect(Self.snapshot(of: column) == before)
    // The column follows no pointer at all, so nothing can change later either: no area of it
    // tracks the pointer, and no row or control does.
    let views = [column as NSView] + column.rows + column.rows.flatMap(\.controls)
    #expect(!views.contains { $0.trackingAreas.contains { $0.options.contains(.mouseMoved) } })
  }

  @Test func everyPartStandsInItsSlotInEveryStateAndRow() throws {
    for (name, setup) in Self.arrangements {
      let (column, window) = setup()
      defer { window.close() }
      let rows = column.rows
      try #require(!rows.isEmpty)
      for row in rows {
        for cell in Self.cells(of: row) {
          let slot = try #require(DecisionColumnLayout.slot(of: cell.role))
          let expected = Self.layout.frame(of: slot)
          let frame = column.convert(cell.frame, from: row)
          #expect(frame.minX == Theme.decisionColumnInset + expected.minX, "\(name) \(cell.role)")
          #expect(frame.width == expected.width, "\(name) \(cell.role)")
          #expect(frame.height == Theme.decisionControlSize)
          #expect(frame.width >= 20)
        }
        for reset in row.controls.compactMap({ $0 as? ResetBlockButton }) {
          let place = Self.layout.frame(of: .place)
          #expect(
            column.convert(reset.frame, from: row).minX == Theme.decisionColumnInset + place.minX)
          #expect(reset.frame.width == place.width)
        }
        #expect(row.frame.minX == Theme.decisionColumnInset, "\(name)")
      }
      // The bars of rows one above the other never overlap.
      let bar = Self.layout.barRect
      for (upper, lower) in zip(rows, rows.dropFirst()) {
        #expect(lower.frame.minY + bar.minY >= upper.frame.minY + bar.maxY, "\(name)")
      }
    }
  }

  @Test(arguments: [1.0, 2.0])
  func rowsSitCenteredOnWholePixels(scale: CGFloat) {
    for step in 0..<64 {
      let center = 40 + CGFloat(step) * 0.37
      let frame = Self.layout.rowFrame(centeredOn: center, scale: scale)
      for edge in [frame.minX, frame.maxX, frame.minY, frame.maxY] {
        #expect((edge * scale).rounded() == edge * scale, "edge \(edge) at \(scale)×")
      }
      #expect(abs(frame.midY - center) <= 0.5 / scale + 0.0001, "\(center) at \(scale)×")
    }
    for slot in DecisionColumnLayout.Slot.allCases {
      let frame = Self.layout.frame(of: slot)
      for edge in [frame.minX, frame.maxX] {
        #expect(edge.rounded() == edge, "\(slot)")
      }
    }
  }

  @Test func rowsInTheWindowLieOnItsPixelsAndBesideTheirBlocks() throws {
    let (pane, column, window, _) = Self.resultPane()
    defer { window.close() }
    let scale = window.backingScaleFactor
    // Scrolled by part of a row, so that the rows of the text lie between whole points.
    pane.scroll(to: CGPoint(x: 0, y: 7.5))
    for row in column.rows {
      let frame = column.convert(row.frame, to: nil)
      for edge in [frame.minY, frame.maxY, frame.minX, frame.maxX] {
        #expect(abs((edge * scale).rounded() - edge * scale) < 0.001, "\(row.block): \(edge)")
      }
      let block = pane.content.blocks[row.block]
      guard !block.rows.isEmpty, let center = pane.rowCenter(ofBlock: row.block) else { continue }
      #expect(abs(row.frame.midY - center) <= 0.5, "\(row.block)")
    }
  }

  @Test func aClickAtEachCellHitsThatCellInEveryState() throws {
    for (name, setup) in Self.arrangements {
      let (column, window) = setup()
      defer { window.close() }
      for row in column.rows where column.bounds.contains(row.frame) {
        for control in row.controls {
          let frame = column.convert(control.frame, from: row)
          for point in [
            CGPoint(x: frame.midX, y: frame.midY), CGPoint(x: frame.minX + 1, y: frame.minY + 1),
            CGPoint(x: frame.maxX - 1, y: frame.maxY - 1),
          ] {
            let hit = column.hitTest(column.convert(point, to: column.superview))
            #expect(hit === control, "\(name), block \(row.block) at \(point)")
          }
        }
      }
    }
  }

  @Test func aClickOnTheWarningSignMakesTheBlockCurrentAndSwitchesNothing() throws {
    let (pane, column, window, recorder) = Self.resultPane()
    defer { window.close() }
    pane.currentBlock = nil
    let row = Self.row(.open, in: column)
    let place = column.convert(Self.layout.frame(of: .place), from: row)
    let point = CGPoint(x: place.midX, y: place.midY)
    #expect(column.hitTest(column.convert(point, to: column.superview)) === column)
    try Clicking.click(column, at: point)
    #expect(recorder.clicked == [SampleResult.Block.open.rawValue])
    #expect(recorder.switched.isEmpty)
  }

  @Test func cellsOfASharedToggleSwitchTogetherAndCountOnce() throws {
    let (_, column, window, recorder) = Self.resultPane()
    defer { window.close() }
    let row = Self.row(.automaticB, in: column)
    let cells = Self.cells(of: row)
    // The base and A share the first toggle.
    #expect(cells.map(\.index) == [0, 0, 1])
    #expect(cells.map(\.isPrimary) == [true, false, true])
    #expect(cells.map { $0.isAccessibilityElement() } == [true, false, true])
    #expect(cells.allSatisfy { !$0.acceptsFirstResponder })
    column.navigatesWithKeyboard = true
    #expect(cells.map(\.acceptsFirstResponder) == [true, false, true])
    #expect(row.accessibilityChildren()?.count == 2)
    #expect(cells[0].accessibilityLabel() == "A and Base")
    cells[1].performClick(nil)
    cells[0].performClick(nil)
    let block = SampleResult.Block.automaticB.rawValue
    #expect(
      recorder.switched == [Switch(toggle: 0, block: block), Switch(toggle: 0, block: block)])
    // Pressing one cell shows both pressed.
    cells[1].isHighlighted = true
    #expect(cells[0].looksPressed && !cells[2].looksPressed)
    cells[1].isHighlighted = false
    #expect(!cells[0].looksPressed)
  }

  @Test func underKeyboardNavigationTheBarWorksLikeASegmentedControl() throws {
    let (_, column, window, recorder) = Self.resultPane()
    defer { window.close() }
    let block = SampleResult.Block.chosenA.rawValue
    #expect(!column.focusToggles(ofBlock: block))
    column.navigatesWithKeyboard = true
    #expect(column.focusToggles(ofBlock: block))
    let controls = Self.row(.chosenA, in: column).controls
    #expect(window.firstResponder === controls[0])
    func press(_ key: Int) throws {
      let characters = String(Character(try #require(UnicodeScalar(key))))
      let event = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: window.windowNumber, context: nil, characters: characters,
          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0))
      (window.firstResponder as? NSView)?.keyDown(with: event)
    }
    try press(NSLeftArrowFunctionKey)
    #expect(window.firstResponder === controls[0], "stays at the start")
    try press(NSRightArrowFunctionKey)
    try press(NSRightArrowFunctionKey)
    #expect(window.firstResponder === controls[2])
    try press(0x20)
    #expect(recorder.switched == [Switch(toggle: 2, block: block)])
    try press(NSRightArrowFunctionKey)
    #expect(window.firstResponder is ResetBlockButton)
    try press(NSRightArrowFunctionKey)
    #expect(window.firstResponder is ResetBlockButton, "stays at the end")
  }

  @Test func togglesSpeakAsToggleButtonsOnOrOff() throws {
    let (_, column, window, _) = Self.resultPane()
    defer { window.close() }
    let row = Self.row(.chosenA, in: column)
    let toggles = Self.cells(of: row)
    #expect(toggles.map { $0.accessibilityLabel() } == ["A", "Base", "B"])
    #expect(toggles.allSatisfy { $0.accessibilityRole() == .checkBox })
    #expect(toggles.allSatisfy { $0.accessibilitySubrole() == .toggle })
    #expect(toggles.map { $0.accessibilityValue() as? NSNumber } == [1, 0, 0])
    #expect(toggles[0].accessibilityHelp() == "Take the version of feature/login.")
    #expect(toggles[0].toolTip == "Take the version of feature/login.")
    #expect(row.accessibilityRole() == .group)
    #expect(row.accessibilityLabel() == "Line 13")
    #expect(row.accessibilityValue() as? String == "Chosen: A")
    let reset = try #require(row.controls.compactMap { $0 as? ResetBlockButton }.first)
    #expect(reset.accessibilityLabel() == "Reset Block")
    #expect(row.accessibilityChildren()?.last as? NSView === reset)
    let deletion = Self.cells(of: Self.row(.nothingTaken, in: column))
    #expect(
      deletion.filter(\.isPrimary).map { $0.accessibilityLabel() } == [
        "A and Base", "B, removes these lines",
      ])
  }

  @Test func pressingAToggleOrTheArrowTellsTheDelegateAndChangesNothingOnItsOwn() throws {
    let (_, column, window, recorder) = Self.resultPane()
    defer { window.close() }
    let block = SampleResult.Block.chosenA.rawValue
    let row = Self.row(.chosenA, in: column)
    let toggles = Self.cells(of: row)
    toggles[2].performClick(nil)
    #expect(toggles[2].accessibilityPerformPress())
    let reset = try #require(row.controls.compactMap { $0 as? ResetBlockButton }.first)
    reset.performClick(nil)
    #expect(
      recorder.switched == [Switch(toggle: 2, block: block), Switch(toggle: 2, block: block)])
    #expect(recorder.resets == [block])
    #expect(toggles[2].accessibilityValue() as? NSNumber == 0)
    // The owner answers with the new decision; the same cells show it, and the focus stays.
    window.makeFirstResponder(toggles[2])
    var decision = try #require(column.decisions[block])
    decision.state = .chosen([.a, .b])
    decision.toggles[2].isOn = true
    column.decisions[block] = decision
    let shown = Self.cells(of: Self.row(.chosenA, in: column))
    #expect(shown.map(ObjectIdentifier.init) == toggles.map(ObjectIdentifier.init))
    #expect(shown[2].accessibilityValue() as? NSNumber == 1)
    #expect(shown[2].face == .chosen)
    #expect(window.firstResponder === shown[2])
  }

  @Test func clickBesideABlockNamesItAndGivesThePaneTheFocusWithoutTextMode() throws {
    let (pane, column, window, recorder) = Self.resultPane()
    defer { window.close() }
    window.makeFirstResponder(nil)
    let block = SampleResult.Block.chosenB.rawValue
    let rowHeight = pane.theme.rowHeight
    let row = try #require(pane.content.blocks[block].rows.first)
    let width = column.bounds.width
    // The column takes the focus, which leaves single keys to the commands, ...
    try Clicking.click(column, at: CGPoint(x: width - 1, y: (CGFloat(row) + 0.5) * rowHeight))
    #expect(window.firstResponder === column)
    #expect(pane.holdsFocus)
    // ... unless the text has it already, which keeps its insertion point for typing.
    window.makeFirstResponder(pane.documentView)
    let caret = pane.documentView.selectedRange()
    try Clicking.click(column, at: CGPoint(x: width - 1, y: 0.5 * rowHeight))
    #expect(window.firstResponder === pane.documentView)
    #expect(pane.documentView.selectedRange() == caret)
    #expect(pane.content.blockIndex(atRow: 0) == nil)
    #expect(recorder.clicked == [block])
    // A control gives the pane the focus through its column as its click starts.
    for control in column.rows.flatMap(\.controls) {
      #expect(control.enclosingColumn === column)
    }
  }

  @Test func rowsAtTheStartAndTheEndOfTheTextGiveWayInwards() throws {
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
    column.decisions = Dictionary(
      uniqueKeysWithValues: (0..<4).map { ($0, Self.automatic([.a, .b])) })
    let recorder = DecisionRecorder()
    column.delegate = recorder
    pane.decisionColumn = column
    let window = Rendering.host(pane, size: CGSize(width: 400, height: 400), isKey: true)
    defer { window.close() }
    let text = 0...CGFloat(rowCount) * pane.theme.rowHeight
    let rows = column.rows
    try #require(rows.count == 4)
    for row in rows {
      #expect(text.contains(row.frame.minY) && text.contains(row.frame.maxY), "\(row.frame)")
    }
    for (upper, lower) in zip(rows, rows.dropFirst()) {
      #expect(lower.frame.midY - upper.frame.midY >= Self.layout.rowSpacing - 0.5)
    }
    for row in rows {
      try Clicking.click(column, at: CGPoint(x: column.bounds.width - 1, y: row.frame.midY))
    }
    #expect(recorder.clicked == [0, 1, 2, 3])
  }

  @Test func rowsOfAChainStayInPlaceOnTheTextWhileThePaneScrolls() throws {
    let (pane, column, window) = Self.densePane(height: 160)
    defer { window.close() }
    let rowHeight = pane.theme.rowHeight
    func placesOnTheText(scrolledTo row: Int) throws -> [Int: CGFloat] {
      pane.scroll(to: CGPoint(x: 0, y: CGFloat(row) * rowHeight))
      let offset = pane.scrollOrigin.y
      return Dictionary(
        uniqueKeysWithValues: column.rows.map { ($0.block, $0.frame.midY + offset) })
    }
    let early = try placesOnTheText(scrolledTo: 44)
    let late = try placesOnTheText(scrolledTo: 50)
    let shared = Set(early.keys).intersection(late.keys)
    try #require(shared.count > 1, "\(early.keys.sorted()) \(late.keys.sorted())")
    for key in shared {
      #expect(early[key] == late[key], "\(key)")
    }
  }

  @Test(arguments: [10.0, 13.0, 16.0, 24.0])
  func barsOnLinesOneAfterTheOtherStayOnTheirLinesWithAGap(fontSize: CGFloat) throws {
    let theme = Theme(font: .monospacedSystemFont(ofSize: fontSize, weight: .regular))
    let (pane, column, window) = Self.consecutivePane(theme: theme)
    defer { window.close() }
    let layout = column.layout
    let rowHeight = theme.rowHeight
    #expect(layout.barHeight == min(max(rowHeight - 2, 14), 20))
    #expect(layout.segmentWidth >= 20 && layout.height >= 20)
    let rows = column.rows
    try #require(rows.count == 5)
    for row in rows {
      let firstRow = CGFloat(pane.content.blocks[row.block].rows.lowerBound)
      #expect(abs(row.frame.midY - (firstRow + 0.5) * rowHeight) <= 0.5, "\(row.block)")
    }
    let bar = layout.barRect
    for (upper, lower) in zip(rows, rows.dropFirst()) {
      let gap = (lower.frame.minY + bar.minY) - (upper.frame.minY + bar.maxY)
      #expect(gap >= min(Theme.toggleBarGap, rowHeight - layout.barHeight) - 0.5, "gap \(gap)")
    }
  }

  @Test func whereRoomsOfClicksReachIntoEachOtherTheNearestBarTakesTheClick() throws {
    let theme = Theme(font: .monospacedSystemFont(ofSize: 10, weight: .regular))
    let (_, column, window) = Self.consecutivePane(theme: theme)
    defer { window.close() }
    let rows = column.rows
    try #require(rows.count == 5)
    #expect(rows[0].frame.maxY > rows[1].frame.minY, "The rooms of clicks overlap")
    for (index, row) in rows.enumerated() {
      let segment = try #require(row.controls.first)
      let x = column.convert(segment.frame, from: row).midX
      let nearby = [
        row.frame.midY - theme.rowHeight / 2 + 1, row.frame.midY,
        row.frame.midY + theme.rowHeight / 2 - 1,
      ]
      for y in nearby {
        let hit = column.hitTest(column.convert(CGPoint(x: x, y: y), to: column.superview))
        #expect(hit === segment, "row \(index) at \(y)")
      }
    }
  }

  @Test func barThatWasPressedKeepsItsPlaceAndItsNeighborGivesWay() throws {
    let text = (0..<8).map { "line \($0)" }.joined(separator: "\n")
    let pane = PaneView()
    pane.content = PaneContent(
      text: text, lineNumbers: (0..<8).map(Int32.init),
      blocks: [
        PaneBlock(rows: 0..<1, style: .tinted(.a)), PaneBlock(rows: 2..<3, style: .tinted(.b)),
        PaneBlock(rows: 3..<3, style: .unchanged),
      ])
    let column = DecisionColumnView()
    column.decisions = Dictionary(uniqueKeysWithValues: (0..<3).map { ($0, Self.automatic([.a])) })
    pane.decisionColumn = column
    let window = Rendering.host(pane, size: CGSize(width: 500, height: 300), isKey: true)
    defer { window.close() }
    let rowHeight = pane.theme.rowHeight
    let pressed = try #require(column.rows.first { $0.block == 1 })
    let place = pressed.frame
    try #require(pressed.controls.first).performClick(nil)
    // The block loses its line, and the empty block after it now lies on the same line.
    pane.setBlocks(
      [
        PaneBlock(rows: 0..<1, style: .tinted(.a)), PaneBlock(rows: 2..<2, style: .unchanged),
        PaneBlock(rows: 2..<3, style: .tinted(.b)),
      ], previews: [], rowTints: [:])
    let rows = column.rows
    #expect(try #require(rows.first { $0.block == 1 }).frame == place)
    let neighbor = try #require(rows.first { $0.block == 2 })
    #expect(neighbor.frame.midY - place.midY >= rowHeight - 0.5)
  }

  @Test func togglesStayLargeEnoughToClickWhenRowsAreLow() throws {
    let theme = Theme(font: .monospacedSystemFont(ofSize: 10, weight: .regular))
    let (_, column, window, _) = Self.resultPane(theme: theme)
    defer { window.close() }
    #expect(theme.rowHeight < 20)
    let controls = Self.row(.chosenBThenA, in: column).controls
    #expect(controls.count == 4)
    for control in controls {
      #expect(control.frame.width >= 20 && control.frame.height >= 20)
    }
  }

  @Test func blockBehindACollapsedRunShowsNoRow() throws {
    let (pane, column, window, _) = Self.resultPane()
    defer { window.close() }
    pane.collapsedRuns = [CollapsedRun(rows: 3..<6)]
    let rows = try #require(column.accessibilityChildren() as? [DecisionRow])
    #expect(rows.count == 10)
    #expect(rows.first.map(Self.spoken) == "Taken automatically: A, Line 3")
  }

  @Test func rowsOfBlocksAtTheSamePlaceMoveApartAndEachFindsItsBlock() throws {
    // Block 1 lies on the boundary below block 0, block 3 on the boundary above block 4: each
    // pair asks for places half a line apart, closer than a row of toggles.
    let pane = PaneView()
    pane.content = PaneContent(
      text: (0..<9).map { "line \($0)" }.joined(separator: "\n"),
      lineNumbers: (0..<9).map(Int32.init),
      blocks: [
        PaneBlock(rows: 1..<2, style: .tinted(.a)), PaneBlock(rows: 2..<2, style: .unchanged),
        PaneBlock(rows: 2..<6, style: .unchanged), PaneBlock(rows: 6..<6, style: .unchanged),
        PaneBlock(rows: 6..<7, style: .tinted(.b)),
      ])
    let column = DecisionColumnView()
    column.decisions = [
      0: Self.automatic([.a]), 1: Self.automatic([.a, .b]),
      3: BlockDecision(state: .chosen([]), toggles: Self.toggles(on: []), canReset: true),
      4: Self.automatic([.b]),
    ]
    let recorder = DecisionRecorder()
    column.delegate = recorder
    pane.decisionColumn = column
    let window = Rendering.host(pane, size: CGSize(width: 400, height: 200), isKey: true)
    defer { window.close() }
    let rowHeight = pane.theme.rowHeight
    let rows = column.rows
    #expect(rows.map(\.block) == [0, 1, 3, 4])
    for (upper, lower) in zip(rows, rows.dropFirst()) {
      #expect(!upper.frame.intersects(lower.frame))
    }
    // The rows of blocks with rows stay beside their first rows; those on boundaries give way.
    #expect(abs(rows[0].frame.midY - 1.5 * rowHeight) <= 0.5)
    #expect(abs(rows[3].frame.midY - 6.5 * rowHeight) <= 0.5)
    for row in rows {
      for offset in [-(Theme.decisionControlSize / 2 - 1), 0, Theme.decisionControlSize / 2 - 1] {
        try Clicking.click(
          column, at: CGPoint(x: column.bounds.width - 1, y: row.frame.midY + offset))
      }
    }
    #expect(recorder.clicked == [0, 0, 0, 1, 1, 1, 3, 3, 3, 4, 4, 4])
  }

  /// Ways to fill the column whose parts the alignment tests check: the sample in each state,
  /// current or not, and many blocks close together.
  static var arrangements: [(String, () -> (DecisionColumnView, NSWindow))] {
    [
      (
        "sample",
        {
          let (pane, column, window, _) = resultPane()
          pane.currentBlock = nil
          return (column, window)
        }
      ),
      (
        "sample with the open conflict current",
        {
          let (_, column, window, _) = resultPane()
          return (column, window)
        }
      ),
      (
        "dense blocks",
        {
          let (_, column, window) = densePane(height: 600)
          return (column, window)
        }
      ),
      (
        "dense blocks scrolled by part of a row",
        {
          let (pane, column, window) = densePane(height: 600)
          pane.scroll(to: CGPoint(x: 0, y: 30 * pane.theme.rowHeight + 5.25))
          return (column, window)
        }
      ),
    ]
  }

  /// A pane of 100 lines whose lines 40 to 51 are blocks of one row, each followed by a block
  /// without rows, so that two rows of toggles ask for each line and push each other far down,
  /// in every state of the column.
  static func densePane(height: CGFloat) -> (PaneView, DecisionColumnView, NSWindow) {
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
    let states: [BlockDecision] = [
      automatic([.a]), automatic([.a, .b]),
      BlockDecision(state: .chosen([.b, .a]), toggles: toggles(on: [.a, .b]), canReset: true),
      BlockDecision(state: .chosen([]), toggles: toggles(on: []), canReset: true),
      BlockDecision(state: .open, toggles: toggles(on: [])),
      BlockDecision(state: .edited, toggles: toggles(on: [.base]), canReset: true),
      BlockDecision(
        state: .chosen([.b]),
        toggles: [
          SampleResult.toggle([.base, .a], isOn: false),
          DecisionToggle(roles: [.b], isOn: true, isDeletion: true, help: ""),
        ], canReset: true),
    ]
    let column = DecisionColumnView()
    column.decisions = Dictionary(
      uniqueKeysWithValues: blocks.indices.map { ($0, states[$0 % states.count]) })
    pane.decisionColumn = column
    let window = Rendering.host(pane, size: CGSize(width: 500, height: height), isKey: true)
    pane.scroll(to: CGPoint(x: 0, y: 36 * pane.theme.rowHeight))
    return (pane, column, window)
  }

  /// A pane of 12 lines with four blocks of one line one after the other, from line 2 on, and a
  /// block of three lines after a gap, each taken from A by the merge.
  static func consecutivePane(theme: Theme) -> (PaneView, DecisionColumnView, NSWindow) {
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(
      text: (0..<12).map { "line \($0)" }.joined(separator: "\n"),
      lineNumbers: (0..<12).map(Int32.init),
      blocks: [
        PaneBlock(rows: 2..<3, style: .tinted(.a)), PaneBlock(rows: 3..<4, style: .tinted(.b)),
        PaneBlock(rows: 4..<5, style: .tinted(.a)), PaneBlock(rows: 5..<6, style: .tinted(.b)),
        PaneBlock(rows: 7..<10, style: .tinted(.a)),
      ])
    let column = DecisionColumnView()
    column.theme = theme
    column.decisions = Dictionary(uniqueKeysWithValues: (0..<5).map { ($0, automatic([.a])) })
    pane.decisionColumn = column
    let window = Rendering.host(pane, size: CGSize(width: 500, height: 400), isKey: true)
    return (pane, column, window)
  }

  /// The three toggles A, Base and B, those of `on` switched on.
  static func toggles(on: Set<ColorRole>) -> [DecisionToggle] {
    [ColorRole.a, .base, .b].map { SampleResult.toggle([$0], isOn: on.contains($0)) }
  }

  /// A block that the merge took from `roles`.
  static func automatic(_ roles: [ColorRole]) -> BlockDecision {
    BlockDecision(state: .automatic(roles), toggles: toggles(on: Set(roles)))
  }

  /// What a user sees of `column`: each row's block, frame and label, and each control's frame,
  /// face and value.
  static func snapshot(of column: DecisionColumnView) -> [String] {
    column.subviews.flatMap { view -> [String] in
      guard let row = view as? DecisionRow else { return ["\(type(of: view)) \(view.frame)"] }
      return ["\(row.block) \(row.frame) \(row.accessibilityLabel() ?? "") \(row.alphaValue)"]
        + row.subviews.map { control in
          let face = (control as? DecisionToggleButton).map { "\($0.face) \($0.toggle.isOn)" }
          return "  \(type(of: control)) \(control.frame) \(face ?? "") \(control.alphaValue)"
        }
    }
  }

  /// What VoiceOver says of `row`: its state, then its line.
  static func spoken(_ row: DecisionRow) -> String {
    [row.accessibilityValue() as? String, row.accessibilityLabel()].compactMap(\.self)
      .joined(separator: ", ")
  }

  /// The row of `block` in `column`.
  static func row(_ block: SampleResult.Block, in column: DecisionColumnView) -> DecisionRow {
    guard let row = column.rows.first(where: { $0.block == block.rawValue }) else {
      preconditionFailure("The column shows no row for \(block)")
    }
    return row
  }

  /// The toggle cells of `row`, from A to B.
  static func cells(of row: DecisionRow) -> [DecisionToggleButton] {
    row.controls.compactMap { $0 as? DecisionToggleButton }
  }

  private static func name(_ role: ColorRole) -> String {
    DecisionToggleButton.name(of: role)
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
