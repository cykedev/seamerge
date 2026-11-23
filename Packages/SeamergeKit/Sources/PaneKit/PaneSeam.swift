package import AppKit
import TextBasics

/// The seam between two panes side by side: a strip that may connect their changes with bands,
/// and may hold a button at each changed block that copies it to a side that can be written.
///
/// Where the panes connect their changes rather than line up their rows, the seam draws a band
/// for each changed block, from its rows in the left pane to its rows in the right
/// (``showsBands``). The top and bottom edges of a band are cubic curves that leave and reach the
/// panes level. A band goes over from the tint of the block on the left to its tint on the
/// right, and its edges carry on the hairlines at the edges of the block. Where a pane has no rows
/// in the block, its end of the band is a point on the hairline that marks the place, so that the
/// band is a wedge. Unchanged rows have no band, nor have blocks in which the two panes do not
/// differ (``blocksWithoutBand``).
///
/// Where a side can be written, the seam has a button at each changed block that copies it there
/// (``copyDirections``): an arrow toward that side, or a bin where the other side has no lines
/// in the block. Without bands, it stands at the first row of the block; with a button for each
/// side, the seam is wider, the arrow to the right in its left half and the arrow to the left in
/// its right half. With bands, each band starts on the side the text comes from with a flat
/// piece as high as the block, which the button stands on at the first row; the band turns
/// beyond it, and the seam is wider by the room the band keeps to turn. Where that side has no
/// rows, the bin stands on the line of the place, as large as the arrows, and the band starts as
/// a tip beside it, with no edge under the bin. No symbol touches a line, an edge or another
/// symbol: a symbol is lower than a row by its margins, a bin at the top and the bottom of the
/// rows moves within them, and beside a bin one row away it is drawn smaller. Nothing appears
/// under the pointer.
///
/// The seam draws only what is in view, from the blocks of the panes, their rows as they show
/// them and where they are scrolled to; it lays out no text, and makes buttons only for the
/// blocks in view. Clicks beside the buttons pass through, so that the divider below stays
/// draggable, and VoiceOver passes the seam by but for its buttons: the bands repeat what the
/// place, the tints and the marks of the panes say.
package final class PaneSeam: NSView {
  /// The pane to the left of the seam.
  package private(set) weak var leftPane: PaneView?

  /// The pane to the right of the seam.
  package private(set) weak var rightPane: PaneView?

  /// The fonts, metrics and colors of the panes.
  package var theme = Theme() {
    didSet {
      symbols.removeAll()
      for button in buttons.values {
        button.theme = theme
      }
      panesDidChange()
    }
  }

  /// The blocks in which the panes on either side do not differ, which get no band, as where
  /// only the other side of a merge changed; none at first.
  package var blocksWithoutBand = IndexSet() {
    didSet {
      if blocksWithoutBand != oldValue {
        needsDisplay = true
      }
    }
  }

  /// A side that the seam copies changes to.
  package enum CopyDirection: Sendable, Hashable, CaseIterable {
    /// To the pane on the right, from the one on the left.
    case toRight

    /// To the pane on the left, from the one on the right.
    case toLeft
  }

  /// What a button that copies in one direction is called, for VoiceOver and its help tag.
  package struct CopyText: Equatable {
    /// The name of the button as a format that takes the number of its change, counted from 1,
    /// such as “Copy Change %lld to Right”.
    package var titleFormat: String

    /// What the button does, naming the side it copies to.
    package var help: String

    /// The help tag of the button.
    package var toolTip: String

    /// The name of the button where the other side has no lines, so that it removes them, as a
    /// format that takes the number of its change.
    package var removalTitleFormat: String

    /// What the button does where it removes lines.
    package var removalHelp: String

    /// The help tag of the button where it removes lines.
    package var removalToolTip: String

    package init(
      titleFormat: String, help: String, toolTip: String, removalTitleFormat: String,
      removalHelp: String, removalToolTip: String
    ) {
      self.titleFormat = titleFormat
      self.help = help
      self.toolTip = toolTip
      self.removalTitleFormat = removalTitleFormat
      self.removalHelp = removalHelp
      self.removalToolTip = removalToolTip
    }
  }

  /// Whether the buttons take presses: not while the window compares its files anew, as the
  /// commands they carry out are invalid meanwhile; on at first.
  package var copyButtonsAreEnabled = true {
    didSet {
      for button in buttons.values {
        button.isEnabled = copyButtonsAreEnabled
      }
    }
  }

  /// Whether the seam connects the changes of the panes with bands, as it does where the panes
  /// show the lines of their files as they are; else it is a quiet strip; on at first.
  package var showsBands = true {
    didSet {
      if showsBands != oldValue {
        panesDidChange()
      }
    }
  }

  /// The sides that changes may be copied to, each of which gets a button at every block of
  /// ``copiedBlocks``; none at first.
  ///
  /// With both, the seam is ``Theme/wideSeamWidth`` wide, else ``Theme/seamWidth``.
  package var copyDirections: Set<CopyDirection> = [] {
    didSet {
      if copyDirections != oldValue {
        panesDidChange()
      }
    }
  }

  /// The blocks that the buttons copy, by their index among the panes' blocks: the blocks in
  /// which the panes differ; none at first.
  package var copiedBlocks = IndexSet() {
    didSet {
      if copiedBlocks != oldValue {
        panesDidChange()
      }
    }
  }

  /// The blocks in which copying in a direction removes lines, as the side the text comes from
  /// has none there; their buttons show a bin.
  package var removingBlocks: [CopyDirection: IndexSet] = [:] {
    didSet {
      if removingBlocks != oldValue {
        panesDidChange()
      }
    }
  }

  /// What the buttons of each direction are called.
  package var copyTexts: [CopyDirection: CopyText] = [:] {
    didSet {
      guard copyTexts != oldValue else { return }
      for button in buttons.values {
        if let text = copyTexts[button.direction] {
          button.show(text)
        }
      }
    }
  }

  /// Learns which buttons the user presses; the seam does not retain it.
  package weak var delegate: (any PaneSeamDelegate)?

  /// How wide the seam is: room for a band to turn and for the buttons it has, beside which a
  /// band keeps its room to turn.
  package var width: CGFloat {
    let width = copyDirections.count > 1 ? Theme.wideSeamWidth : Theme.seamWidth
    return showsBands && !copyDirections.isEmpty ? width + Theme.bandRoomBesideButtons : width
  }

  /// The width of the flat piece at the left and the right end of every band, where the
  /// buttons that copy from that side stand; none without bands.
  private var stubs: (left: CGFloat, right: CGFloat) {
    guard showsBands else { return (0, 0) }
    return (
      copyDirections.contains(.toRight) ? Theme.bandStubWidth : 0,
      copyDirections.contains(.toLeft) ? Theme.bandStubWidth : 0
    )
  }

  /// The room between a symbol at the seam and any line or other symbol, with a pixel of the
  /// screen kept for rounding the places of symbols to pixels.
  private var symbolMargin: CGFloat {
    Theme.copySymbolMargin + hairlineWidth
  }

  /// The largest size of a symbol at the seam: as wide as the flat piece leaves room for, and
  /// lower than a row by its margins.
  private var largestSymbolSize: CGSize {
    let rowHeight = (leftPane?.theme ?? theme).rowHeight
    return CGSize(
      width: Theme.bandStubWidth - 2 * symbolMargin, height: rowHeight - 2 * symbolMargin)
  }

  /// The size of the symbol `name` at the seam: its own, made smaller to the largest size.
  private func symbolSize(named name: String) -> CGSize {
    guard
      let size = symbols.image(
        named: name, pointSize: theme.copySymbolSize, weight: .semibold,
        color: Theme.secondaryMarkColor)?.size, size.width > 0, size.height > 0
    else { return .zero }
    let largest = largestSymbolSize
    let factor = min(largest.width / size.width, largest.height / size.height, 1)
    return CGSize(width: size.width * factor, height: size.height * factor)
  }

  /// Where a bin stands on the line of a side without rows: its vertical middle, and the height
  /// it may be drawn at where it is smaller than the arrows.
  private struct BinPlace {
    var middle: CGFloat
    var height: CGFloat?
  }

  /// Whether `block` gets a bin on the side of `pane`, for the button that copies in
  /// `direction`: the side has no rows there, and the seam draws bands.
  private func hasBin(_ block: Int, in pane: PaneView, toward direction: CopyDirection) -> Bool {
    showsBands && copyDirections.contains(direction) && copiedBlocks.contains(block)
      && pane.content.blocks.indices.contains(block) && pane.content.blocks[block].rows.isEmpty
  }

  /// Where the bin of `block` stands on the side of `pane`, for the button that copies in
  /// `direction`, or `nil` where it has none.
  ///
  /// The bin is as large as the arrows and stands on the line of its place, moved within the
  /// rows of the pane at their top and their bottom. It is drawn smaller only beside the bin of
  /// a neighboring block on the same side, so close that the two would touch; only the direct
  /// neighbors count, and each pair comes out the same from either of its bins, so that no
  /// bin depends on bins further away.
  private func binPlace(
    ofBlock block: Int, in pane: PaneView, toward direction: CopyDirection
  ) -> BinPlace? {
    guard hasBin(block, in: pane, toward: direction) else { return nil }
    let margin = symbolMargin
    let line = extent(of: block, in: pane).lowerBound
    let offset = convert(CGPoint.zero, from: pane.documentView).y
    let rows = pane.verticalSpan(ofRows: 0..<pane.content.lineNumbers.count)
    let (top, bottom) = (rows.lowerBound + offset, rows.upperBound + offset)
    let natural = symbolSize(named: "trash").height
    var height = natural
    for neighbor in [block - 1, block + 1] where hasBin(neighbor, in: pane, toward: direction) {
      let other = extent(of: neighbor, in: pane).lowerBound
      let (upper, lower) = (min(line, other), max(line, other))
      var limit = lower - upper - margin
      // A bin at the top or the bottom of the rows moves within them by half its height.
      if upper - top < natural / 2 + margin {
        limit = min(limit, (lower - top - 2 * margin) * 2 / 3)
      }
      if bottom - lower < natural / 2 + margin {
        limit = min(limit, (bottom - upper - 2 * margin) * 2 / 3)
      }
      height = min(height, max(limit, 0))
    }
    let highest = top + margin + height / 2
    let lowest = max(bottom - margin - height / 2, highest)
    return BinPlace(
      middle: min(max(line, highest), lowest), height: height < natural ? height : nil)
  }

  /// The buttons of the blocks in view, by their block and direction.
  private var buttons: [ButtonKey: CopyChangeButton] = [:]

  /// The frames of the buttons when they were last placed, to tell when they moved.
  private var buttonFrames: [ButtonKey: CGRect] = [:]

  /// The symbols of the buttons, made once.
  private let symbols = SymbolImages()

  /// The block and direction of a button.
  private struct ButtonKey: Hashable {
    var block: Int
    var direction: CopyDirection
  }

  /// Creates the seam between `leftPane` and `rightPane`, which tell it when what they show
  /// changes, in place of any seam they had on that side.
  package init(between leftPane: PaneView, and rightPane: PaneView) {
    self.leftPane = leftPane
    self.rightPane = rightPane
    super.init(frame: .zero)
    // Views draw beyond their bounds unless told otherwise, and the dirty rectangle may reach
    // past them.
    clipsToBounds = true
    attach()
  }

  /// Seams are never archived.
  package required init?(coder: NSCoder) {
    nil
  }

  isolated deinit {
    detach()
  }

  /// A seam taken out of its view stops hearing from its panes; put back, it hears again.
  package override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    if superview == nil {
      detach()
    } else {
      attach()
    }
  }

  /// Has the panes tell the seam when what they show changes.
  private func attach() {
    leftPane?.trailingSeam = self
    rightPane?.leadingSeam = self
  }

  /// Has the panes stop telling the seam, if it is still theirs.
  private func detach() {
    if leftPane?.trailingSeam === self {
      leftPane?.trailingSeam = nil
    }
    if rightPane?.leadingSeam === self {
      rightPane?.leadingSeam = nil
    }
  }

  package override var isFlipped: Bool { true }

  package override var isOpaque: Bool { true }

  /// Draws the seam again and places its buttons anew, after the rows, blocks or scroll
  /// position of a pane changed.
  func panesDidChange() {
    needsDisplay = true
    needsLayout = true
  }

  /// Clicks and drags beside the buttons pass through to the divider below; where the click
  /// areas of two buttons overlap, as with low rows, the one whose middle lies nearest takes the
  /// click.
  package override func hitTest(_ point: NSPoint) -> NSView? {
    let local = convert(point, from: superview)
    guard !isHidden, bounds.contains(local) else { return nil }
    func distance(_ button: CopyChangeButton) -> CGFloat {
      hypot(button.frame.midX - local.x, button.frame.midY - local.y)
    }
    return buttons.values.filter { $0.frame.contains(local) }.min { first, second in
      (distance(first), first.block, first.direction == .toRight ? 0 : 1)
        < (distance(second), second.block, second.direction == .toRight ? 0 : 1)
    }
  }

  package override func isAccessibilityElement() -> Bool {
    false
  }

  /// The buttons in view, from top to bottom, and in each row from left to right.
  package override func accessibilityChildren() -> [Any]? {
    copyButtons
  }

  package override func layout() {
    super.layout()
    placeButtons()
  }

  /// The buttons in view, from top to bottom, and in each row from left to right.
  package var copyButtons: [CopyChangeButton] {
    buttons.values.filter { bounds.intersects($0.frame) }.sorted {
      ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX)
    }
  }

  /// Gives each block in view that the seam copies a button for each direction, where it
  /// belongs, and takes the buttons from the blocks out of view.
  private func placeButtons() {
    var placed: Set<ButtonKey> = []
    if !copyDirections.isEmpty, let leftPane, let rightPane, let area = textArea {
      let size = Theme.copyButtonSize
      let scale = window?.backingScaleFactor ?? 2
      let rowHeight = leftPane.theme.rowHeight
      for place in buttonPlaces(in: area, leftPane: leftPane, rightPane: rightPane) {
        let key = ButtonKey(block: place.block, direction: place.direction)
        let center = CGPoint(x: place.x, y: place.top + rowHeight / 2)
        guard area.minY...area.maxY ~= center.y else { continue }
        let button = buttons[key] ?? makeButton(for: key)
        // The click area lies wholly within the seam; the symbol keeps its place within it.
        let x = min(max(center.x - size / 2, bounds.minX), bounds.maxX - size)
        let y = min(max(center.y - size / 2, bounds.minY), bounds.maxY - size)
        button.frame = CGRect(
          x: (x * scale).rounded() / scale, y: (y * scale).rounded() / scale, width: size,
          height: size)
        button.symbolOffset = CGSize(
          width: ((center.x - button.frame.midX) * scale).rounded() / scale,
          height: ((center.y - button.frame.midY) * scale).rounded() / scale)
        button.removesLines = removingBlocks[place.direction]?.contains(place.block) == true
        button.largestSymbolSize = CGSize(
          width: largestSymbolSize.width, height: place.symbolHeight ?? largestSymbolSize.height)
        button.isCurrent =
          leftPane.currentBlock == place.block || rightPane.currentBlock == place.block
        placed.insert(key)
      }
    }
    for (key, button) in buttons where !placed.contains(key) {
      button.removeFromSuperview()
      buttons[key] = nil
    }
    // The view the seam lies over gives its divider the cursor around the buttons, which show
    // the arrow; it reads them anew once they moved.
    let frames = buttons.mapValues(\.frame)
    if frames != buttonFrames {
      buttonFrames = frames
      if let superview {
        window?.invalidateCursorRects(for: superview)
      }
    }
  }

  /// Where a button stands: its block and direction, the middle of its width and the top of the
  /// first row it stands at.
  private struct ButtonPlace {
    var block: Int
    var direction: CopyDirection
    var x: CGFloat
    var top: CGFloat
    /// The height a bin may be drawn at, or `nil` for the largest size.
    var symbolHeight: CGFloat?
  }

  /// The places of the buttons of the blocks whose first row is in view of `area`.
  private func buttonPlaces(
    in area: CGRect, leftPane: PaneView, rightPane: PaneView
  ) -> [ButtonPlace] {
    let count = min(leftPane.content.blocks.count, rightPane.content.blocks.count)
    let reach = Theme.copyButtonSize
    let first = (0..<count).partitioningIndex { index in
      max(extent(of: index, in: leftPane).lowerBound, extent(of: index, in: rightPane).lowerBound)
        >= area.minY - reach
    }
    let directions = CopyDirection.allCases.filter(copyDirections.contains)
    var places: [ButtonPlace] = []
    for index in first..<count {
      let left = extent(of: index, in: leftPane).lowerBound
      let right = extent(of: index, in: rightPane).lowerBound
      guard min(left, right) <= area.maxY + reach else { break }
      guard copiedBlocks.contains(index) else { continue }
      for direction in directions {
        let isFromLeft = direction == .toRight
        let x: CGFloat
        var top = left
        var symbolHeight: CGFloat?
        if showsBands {
          // On the flat piece at the start of the band, on the side the text comes from, at the
          // first row of the block, or on the line the band comes out of where it has none.
          x = isFromLeft ? bounds.minX + stubs.left / 2 : bounds.maxX - stubs.right / 2
          top = isFromLeft ? left : right
          if let bin = binPlace(
            ofBlock: index, in: isFromLeft ? leftPane : rightPane, toward: direction)
          {
            top = bin.middle - leftPane.theme.rowHeight / 2
            symbolHeight = bin.height
          }
        } else if directions.count == 1 {
          x = bounds.midX
        } else {
          x = isFromLeft ? bounds.minX + bounds.width / 4 : bounds.maxX - bounds.width / 4
        }
        places.append(
          ButtonPlace(
            block: index, direction: direction, x: x, top: top, symbolHeight: symbolHeight))
      }
    }
    return places
  }

  private func makeButton(for key: ButtonKey) -> CopyChangeButton {
    let button = CopyChangeButton(
      block: key.block, direction: key.direction, theme: theme, symbols: symbols,
      text: copyTexts[key.direction]
        ?? CopyText(
          titleFormat: "", help: "", toolTip: "", removalTitleFormat: "", removalHelp: "",
          removalToolTip: ""))
    button.isEnabled = copyButtonsAreEnabled
    button.target = self
    button.action = #selector(copyButtonWasPressed(_:))
    addSubview(button)
    buttons[key] = button
    return button
  }

  @objc private func copyButtonWasPressed(_ sender: CopyChangeButton) {
    delegate?.seam(self, didAskToCopyBlock: sender.block, in: sender.direction)
  }

  package override func draw(_ dirtyRect: NSRect) {
    let dirtyRect = dirtyRect.intersection(bounds)
    guard let context = NSGraphicsContext.current?.cgContext, !dirtyRect.isEmpty else { return }
    Theme.backgroundColor.setFill()
    dirtyRect.fill()
    if showsBands, let area = textArea {
      context.saveGState()
      context.clip(to: area)
      for band in bands where band.verticalExtent.overlaps(dirtyRect.minY...dirtyRect.maxY) {
        draw(band, in: context)
      }
      context.restoreGState()
    }
    let hairline = hairlineWidth
    NSColor.separatorColor.setFill()
    for x in [bounds.minX, bounds.maxX - hairline] {
      CGRect(x: x, y: dirtyRect.minY, width: hairline, height: dirtyRect.height).fill()
    }
  }

  /// A band as the seam draws it: the vertical extent of its block at either edge of the seam,
  /// in the seam's coordinates, measured along the hairlines at the block's edges.
  struct Band: Equatable {
    /// The index of the block among the panes' blocks.
    var block: Int
    /// From the hairline at the top of the block to the one at its bottom, in the left pane.
    var left: ClosedRange<CGFloat>
    /// From the hairline at the top of the block to the one at its bottom, in the right pane.
    var right: ClosedRange<CGFloat>
    /// How the block's rows are tinted in the left pane.
    var leftStyle: BlockStyle
    /// How the block's rows are tinted in the right pane.
    var rightStyle: BlockStyle
    /// Whether the block is the current one.
    var isCurrent: Bool

    /// From the top of the band to its bottom.
    var verticalExtent: ClosedRange<CGFloat> {
      min(left.lowerBound, right.lowerBound)...max(left.upperBound, right.upperBound)
    }
  }

  /// The bands of the blocks that reach into the text area of the panes, in block order, without
  /// the blocks that get none.
  ///
  /// A band whose block lies partly above or below the visible text keeps its ends where the
  /// rows are, beyond the area, so that its edges run as they would if all of it were in view.
  var bands: [Band] {
    guard showsBands, let leftPane, let rightPane, let area = textArea else { return [] }
    let leftBlocks = leftPane.content.blocks
    let rightBlocks = rightPane.content.blocks
    let count = min(leftBlocks.count, rightBlocks.count)
    let first = (0..<count).partitioningIndex { index in
      max(extent(of: index, in: leftPane).upperBound, extent(of: index, in: rightPane).upperBound)
        >= area.minY
    }
    var bands: [Band] = []
    for index in first..<count {
      let left = extent(of: index, in: leftPane)
      let right = extent(of: index, in: rightPane)
      guard min(left.lowerBound, right.lowerBound) <= area.maxY else { break }
      guard !blocksWithoutBand.contains(index) else { continue }
      bands.append(
        Band(
          block: index, left: left, right: right, leftStyle: leftBlocks[index].style,
          rightStyle: rightBlocks[index].style,
          isCurrent: leftPane.currentBlock == index || rightPane.currentBlock == index))
    }
    return bands
  }

  /// The part of the seam beside the visible text of the panes, below their headers.
  private var textArea: CGRect? {
    let areas = [leftPane, rightPane].compactMap { pane -> CGRect? in
      guard let pane, pane.window === window, !pane.isHiddenOrHasHiddenAncestor else { return nil }
      return convert(pane.clipView.bounds, from: pane.clipView)
    }
    guard let first = areas.first else { return nil }
    let top = areas.map(\.minY).reduce(first.minY, max)
    let bottom = areas.map(\.maxY).reduce(first.maxY, min)
    guard bottom > top else { return nil }
    return CGRect(x: bounds.minX, y: top, width: bounds.width, height: bottom - top)
  }

  /// The vertical extent of block `index` in `pane`, in the seam's coordinates, from the middle
  /// of the hairline at its top to the middle of the one at its bottom; for a block without
  /// rows, the middle of the hairline that marks its place.
  private func extent(of index: Int, in pane: PaneView) -> ClosedRange<CGFloat> {
    let rows = pane.content.blocks[index].rows
    let span = pane.verticalSpan(ofRows: rows)
    let offset = convert(CGPoint.zero, from: pane.documentView).y
    let hairline = hairlineWidth
    guard !rows.isEmpty else {
      // The hairline lies at the top of the row below the boundary, or at the bottom of the last
      // row at the end of the text.
      let below = pane.content.hairlineRow(ofBoundary: rows.lowerBound) == rows.lowerBound
      let y = span.lowerBound + offset + (below ? hairline / 2 : -hairline / 2)
      return y...y
    }
    return (span.lowerBound + offset + hairline / 2)...(span.upperBound + offset - hairline / 2)
  }

  /// The thickness of a hairline: one pixel of the screen.
  private var hairlineWidth: CGFloat {
    1 / (window?.backingScaleFactor ?? 2)
  }

  /// Fills `band` and draws its edges.
  private func draw(_ band: Band, in context: CGContext) {
    let shape = outline(of: band)
    let fills = fillColors(of: band)
    if let fills {
      context.saveGState()
      context.addPath(shape.area)
      context.clip()
      drawGradient(from: fills.left, to: fills.right, in: context)
      context.restoreGState()
    }
    let edges = edgeColors(of: band)
    guard let edges else { return }
    context.saveGState()
    context.setLineWidth(hairlineWidth)
    for edge in [shape.top, shape.bottom] {
      context.addPath(edge)
    }
    context.replacePathWithStrokedPath()
    context.clip()
    drawGradient(from: edges.left, to: edges.right, in: context)
    context.restoreGState()
  }

  /// The area of `band` and its top and bottom edges.
  ///
  /// Where a side has no rows and a bin stands on its line, the band starts as a tip beside the
  /// bin, with no edge under it.
  func outline(of band: Band) -> (area: CGPath, top: CGPath, bottom: CGPath) {
    let (minX, maxX) = (bounds.minX, bounds.maxX)
    let (left, right) = (minX + stubs.left, maxX - stubs.right)
    func curve(from start: CGPoint, to end: CGPoint, on path: CGMutablePath) {
      let controls = Self.controlPoints(from: start, to: end)
      path.addCurve(to: end, control1: controls.first, control2: controls.second)
    }
    var (leftEnd, rightEnd) = (band.left, band.right)
    let leftBin = leftPane.flatMap {
      binPlace(ofBlock: band.block, in: $0, toward: .toRight)?.middle
    }
    let rightBin = rightPane.flatMap {
      binPlace(ofBlock: band.block, in: $0, toward: .toLeft)?.middle
    }
    if let leftBin {
      leftEnd = leftBin...leftBin
    }
    if let rightBin {
      rightEnd = rightBin...rightBin
    }
    let (start, end) = (leftBin == nil ? minX : left, rightBin == nil ? maxX : right)
    func edge(from first: CGFloat, to last: CGFloat) -> CGPath {
      let path = CGMutablePath()
      path.move(to: CGPoint(x: start, y: first))
      path.addLine(to: CGPoint(x: left, y: first))
      curve(from: CGPoint(x: left, y: first), to: CGPoint(x: right, y: last), on: path)
      path.addLine(to: CGPoint(x: end, y: last))
      return path
    }
    let area = CGMutablePath()
    area.move(to: CGPoint(x: start, y: leftEnd.lowerBound))
    area.addLine(to: CGPoint(x: left, y: leftEnd.lowerBound))
    curve(
      from: CGPoint(x: left, y: leftEnd.lowerBound),
      to: CGPoint(x: right, y: rightEnd.lowerBound), on: area)
    area.addLine(to: CGPoint(x: end, y: rightEnd.lowerBound))
    area.addLine(to: CGPoint(x: end, y: rightEnd.upperBound))
    area.addLine(to: CGPoint(x: right, y: rightEnd.upperBound))
    curve(
      from: CGPoint(x: right, y: rightEnd.upperBound),
      to: CGPoint(x: left, y: leftEnd.upperBound), on: area)
    area.addLine(to: CGPoint(x: start, y: leftEnd.upperBound))
    area.closeSubpath()
    return (
      area, edge(from: leftEnd.lowerBound, to: rightEnd.lowerBound),
      edge(from: leftEnd.upperBound, to: rightEnd.upperBound)
    )
  }

  /// The control points of the cubic curve of an edge from `start` at one side of the seam to
  /// `end` at the other, which leaves and reaches the panes level.
  ///
  /// The control points lie half way across, as for the bands of a few rows, while the edge
  /// rises or falls by up to twice the width of the seam. Beyond that they move further across,
  /// up to nine tenths of the way at eight times the width, so that a steep edge bends over more
  /// of the width rather than turning sharply where it reaches a pane, as at the point of a
  /// wedge. They stay at the heights of the ends, so the curve never goes beyond them.
  static func controlPoints(
    from start: CGPoint, to end: CGPoint
  ) -> (first: CGPoint, second: CGPoint) {
    let width = abs(end.x - start.x)
    let steepness = width > 0 ? abs(end.y - start.y) / width : 0
    let progress = min(max((steepness - 2) / 6, 0), 1)
    let share = 0.5 + 0.4 * progress * progress * (3 - 2 * progress)
    let across = end.x - start.x
    return (
      CGPoint(x: start.x + across * share, y: start.y),
      CGPoint(x: end.x - across * share, y: end.y)
    )
  }

  /// The fill of `band` at its left and right end, or `nil` if neither side is tinted.
  private func fillColors(of band: Band) -> (left: NSColor, right: NSColor)? {
    let left = theme.rowFill(for: band.leftStyle, isFiller: false, isCurrent: band.isCurrent)
    let right = theme.rowFill(for: band.rightStyle, isFiller: false, isCurrent: band.isCurrent)
    guard left != nil || right != nil else { return nil }
    return (left ?? .clear, right ?? .clear)
  }

  /// The color of the edges of `band` at its left and right end, or `nil` if neither side is
  /// tinted.
  private func edgeColors(of band: Band) -> (left: NSColor, right: NSColor)? {
    let left = theme.edgeColor(between: nil, and: band.leftStyle, isOnlyBoundary: false)
    let right = theme.edgeColor(between: nil, and: band.rightStyle, isOnlyBoundary: false)
    guard left != nil || right != nil else { return nil }
    return (left ?? .clear, right ?? .clear)
  }

  /// Fills the clipped area with a gradient across the seam, from `left` to `right`.
  private func drawGradient(from left: NSColor, to right: NSColor, in context: CGContext) {
    let colors = [left.cgColor, right.cgColor] as CFArray
    guard
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])
    else { return }
    context.drawLinearGradient(
      gradient, start: CGPoint(x: bounds.minX + stubs.left, y: 0),
      end: CGPoint(x: bounds.maxX - stubs.right, y: 0),
      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
  }
}
