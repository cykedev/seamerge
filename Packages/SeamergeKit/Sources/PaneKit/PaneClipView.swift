import AppKit

/// The clip view of a pane, which scrolls its text only to whole pixels of the window.
///
/// The text draws its rows, their tints and hairlines on whole pixels of its own, and a seam
/// beside the pane draws the ends of its bands exactly where those rows are. Scrolled by a
/// fraction of a pixel, as a pane that follows another would be, the text would still show at a
/// whole pixel on the screen, and the edges of the bands would miss the hairlines by up to a
/// pixel. So every scroll position moves to the nearest one at which the text lies on whole
/// pixels, and once more when the window moves to a screen of another scale. Panes that stand
/// together on the same grid round the same way and stay together. The seams still compute
/// their bands exactly; only the place of the text is rounded.
final class PaneClipView: NSClipView {
  // The bounds move in three ways, none of which passes through another, so each rounds: as
  // the user scrolls or magnifies, the clip view asks `constrainBoundsRect(_:)`; `scroll(to:)`,
  // with which a pane scrolls to a place or follows another, does not ask it; and an animation
  // through `animator()`, with which a pane glides to a block, sets `setBoundsOrigin(_:)` frame
  // by frame.

  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    pixelAligned(super.constrainBoundsRect(proposedBounds))
  }

  override func scroll(to newOrigin: NSPoint) {
    super.scroll(to: pixelAligned(CGRect(origin: newOrigin, size: bounds.size)).origin)
  }

  override func setBoundsOrigin(_ newOrigin: NSPoint) {
    super.setBoundsOrigin(pixelAligned(CGRect(origin: newOrigin, size: bounds.size)).origin)
  }

  /// Moves the text to whole pixels of the screen that the window moved to, as from two pixels
  /// per point to one; the panes coupled with this one follow.
  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    let origin = bounds.origin
    scroll(to: origin)
    if bounds.origin != origin {
      enclosingScrollView?.reflectScrolledClipView(self)
    }
  }

  /// `proposedBounds` moved to the nearest place at which the text lies on whole pixels of the
  /// window, within the scroll range of the text if `proposedBounds` lies within it; as given
  /// outside a window.
  private func pixelAligned(_ proposedBounds: NSRect) -> NSRect {
    guard let window, let documentView else { return proposedBounds }
    // Where the top left corner of the text would lie at `proposedBounds`, in the coordinates
    // that the clip view has now, and the nearest place to it on whole pixels; the bounds move
    // by as much as the corner, the other way. Taken from the aligned corner, not as a
    // difference, the result has no rounding errors and compares equal across panes.
    let text = documentView.frame.origin
    let corner = CGRect(
      x: text.x + bounds.minX - proposedBounds.minX, y: text.y + bounds.minY - proposedBounds.minY,
      width: 0, height: 0)
    let alignedCorner = backingAlignedRect(corner, options: .alignAllEdgesNearest)
    var aligned = proposedBounds
    aligned.origin = CGPoint(
      x: text.x + bounds.minX - alignedCorner.minX, y: text.y + bounds.minY - alignedCorner.minY)
    // Rounded beyond an end of the scroll range, the text stops a pixel short of it instead.
    let range = super.constrainBoundsRect(proposedBounds)
    guard range.origin == proposedBounds.origin else { return aligned }
    let pixel = 1 / window.backingScaleFactor
    let limit = super.constrainBoundsRect(aligned)
    if limit.minX != aligned.minX {
      aligned.origin.x += limit.minX < aligned.minX ? -pixel : pixel
    }
    if limit.minY != aligned.minY {
      aligned.origin.y += limit.minY < aligned.minY ? -pixel : pixel
    }
    return super.constrainBoundsRect(aligned) == aligned ? aligned : proposedBounds
  }
}
