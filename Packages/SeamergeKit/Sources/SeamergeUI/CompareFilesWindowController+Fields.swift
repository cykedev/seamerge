import AppKit

extension CompareFilesWindowController: FileFieldDelegate {
  func fileFieldDidAskToChoose(_ field: FileField) {
    guard let window, window.attachedSheet == nil else { return }
    let slot = field.slot
    let role = slot.title(hasBase: selection.hasBase)
    Task {
      guard let url = await panels.chooseFile(for: role, in: window) else { return }
      fill([slot: url])
    }
  }

  func fileFieldDidAskToClear(_ field: FileField) {
    clear(field.slot)
  }

  func operation(forDrag info: any NSDraggingInfo, onto slot: FileSlot?) -> NSDragOperation {
    if let source = info.draggingSource as? FileField {
      guard source.window === window, let slot, slot != source.slot else {
        dropTargets = [:]
        return []
      }
      let swap = String(
        localized: "Drop to Swap", bundle: .module,
        comment: "Compare Files: below two fields while one is dragged onto the other.")
      dropTargets = [slot: swap, source.slot: swap]
      return .move
    }
    guard
      let urls = FileDrop.files(on: info.draggingPasteboard),
      let places = selection.places(for: urls, droppedOn: slot)
    else {
      dropTargets = [:]
      return []
    }
    var dropped = selection
    dropped.fill(places)
    let hasBase = dropped.hasBase
    dropTargets = Dictionary(
      uniqueKeysWithValues: places.keys.map { target in
        let role = target.title(hasBase: hasBase)
        return (
          target,
          String(
            localized: "Drop to Use as \(role)", bundle: .module,
            comment:
              "Compare Files: below a field that a drop would fill, such as Drop to Use as A.")
        )
      })
    return .copy
  }

  func acceptDrop(_ info: any NSDraggingInfo, onto slot: FileSlot?) -> Bool {
    defer { dropTargets = [:] }
    if let source = info.draggingSource as? FileField {
      guard source.window === window, let slot, slot != source.slot else { return false }
      selection.swap(source.slot, slot)
      selectionDidChange()
      announceSwap(of: source.slot, and: slot)
      return true
    }
    guard
      let urls = FileDrop.files(on: info.draggingPasteboard),
      let places = selection.places(for: urls, droppedOn: slot)
    else { return false }
    fill(places)
    return true
  }

  func dragDidEnd() {
    dropTargets = [:]
  }
}
