import AppKit
import MergeModel
import PaneKit

/// The rotors of VoiceOver that move block by block: through the conflicts of a merge, open or
/// decided, and through every change.
///
/// An item is the text of its block in the pane that has the focus, or else in the result of a
/// merge or the newer side of a comparison. Moving to an item reads the block and leaves the
/// current block as it is; the commands of the Go menu make a block current.
@MainActor
final class BlockRotors: NSObject, @MainActor NSAccessibilityCustomRotorItemSearchDelegate {
  /// Which blocks a rotor moves through.
  enum Kind {
    /// The blocks that were conflicts when the files were loaded.
    case conflicts

    /// Every changed block.
    case changes
  }

  private weak var presentation: SessionPresentation?

  /// The rotors: conflicts first, if the window merges, then changes.
  private(set) var rotors: [NSAccessibilityCustomRotor] = []

  private var kinds: [ObjectIdentifier: Kind] = [:]

  /// The changed block of each item handed to VoiceOver, held as long as VoiceOver holds the
  /// item: blocks without rows can share a range of text, so the range does not tell them apart.
  private let blocksOfItems = NSMapTable<NSAccessibilityCustomRotor.ItemResult, NSNumber>
    .weakToStrongObjects()

  /// Creates the rotors of `presentation`.
  init(presentation: SessionPresentation) {
    self.presentation = presentation
    super.init()
    let isMerge = presentation.changes.session.kind == .merge
    for kind in isMerge ? [Kind.conflicts, .changes] : [.changes] {
      let rotor = NSAccessibilityCustomRotor(label: Self.label(of: kind), itemSearchDelegate: self)
      kinds[ObjectIdentifier(rotor)] = kind
      rotors.append(rotor)
    }
  }

  /// The block after or before the item VoiceOver is on, among the blocks of the rotor whose
  /// spoken name contains the filter, if any.
  func rotor(
    _ rotor: NSAccessibilityCustomRotor,
    resultFor searchParameters: NSAccessibilityCustomRotor.SearchParameters
  ) -> NSAccessibilityCustomRotor.ItemResult? {
    guard let presentation, let kind = kinds[ObjectIdentifier(rotor)],
      let pane = Self.targetPane(in: presentation)
    else { return nil }
    let blocks = Self.blocks(of: kind, in: presentation)
    let filter = searchParameters.filterString
    let candidates = blocks.indices.filter { position in
      filter.isEmpty
        || Self.name(of: kind, at: position, among: blocks, in: presentation)
          .localizedStandardContains(filter)
    }
    let currentPosition = searchParameters.currentItem
      .flatMap { blocksOfItems.object(forKey: $0)?.intValue }
      .flatMap { blocks.firstIndex(of: $0) }
    let position =
      switch searchParameters.searchDirection {
      case .previous: candidates.last { $0 < currentPosition ?? blocks.count }
      default: candidates.first { $0 > currentPosition ?? -1 }
      }
    guard let position else { return nil }
    let block = blocks[position]
    let item = NSAccessibilityCustomRotor.ItemResult(targetElement: pane.documentView)
    item.targetRange = pane.textRange(ofRows: pane.content.blocks[block].rows)
    item.customLabel = Self.name(of: kind, at: position, among: blocks, in: presentation)
    blocksOfItems.setObject(NSNumber(value: block), forKey: item)
    return item
  }

  /// The pane whose text the items are: the pane that has the focus, or else the result, or the
  /// last pane side by side.
  private static func targetPane(in presentation: SessionPresentation) -> PaneView? {
    presentation.allPanes.first { $0.holdsFocus && $0.isShown }
      ?? presentation.layout.resultPane ?? presentation.layout.sourcePanes.last?.pane
  }

  /// The indices of the changed blocks that a rotor of `kind` moves through.
  private static func blocks(of kind: Kind, in presentation: SessionPresentation) -> [Int] {
    let blocks = presentation.changes.blocks
    switch kind {
    case .changes: return Array(blocks.indices)
    case .conflicts: return blocks.indices.filter { blocks[$0].kind == .conflict }
    }
  }

  /// What VoiceOver says for the block at `position` among `blocks`, such as “Conflict 2 of 3,
  /// open”.
  private static func name(
    of kind: Kind, at position: Int, among blocks: [Int], in presentation: SessionPresentation
  ) -> String {
    let number = position + 1
    let count = blocks.count
    switch kind {
    case .changes:
      return String(
        localized: "Change \(number) of \(count)", bundle: .module,
        comment: "VoiceOver: an item of the rotor of changes, such as “Change 2 of 9”.")
    case .conflicts:
      let block = presentation.changes.blocks[blocks[position]]
      if presentation.result?.document.segment(for: block).state == .open {
        return String(
          localized: "Conflict \(number) of \(count), open", bundle: .module,
          comment: "VoiceOver: an item of the rotor of conflicts that awaits a decision.")
      }
      return String(
        localized: "Conflict \(number) of \(count), resolved", bundle: .module,
        comment: "VoiceOver: an item of the rotor of conflicts that was decided.")
    }
  }

  private static func label(of kind: Kind) -> String {
    switch kind {
    case .conflicts:
      String(
        localized: "Conflicts", bundle: .module,
        comment:
          "Toolbar items: the count of the open conflicts and the buttons that go through them.")
    case .changes:
      String(
        localized: "Changes", bundle: .module,
        comment: "Toolbar items: the current change and the buttons that go through the changes.")
    }
  }
}
