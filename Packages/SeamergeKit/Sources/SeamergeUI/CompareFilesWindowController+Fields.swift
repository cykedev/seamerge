import AppKit

extension CompareFilesWindowController: FileFieldDelegate {
  func fileFieldDidAskToChoose(_ field: FileField) {
    let slot = field.slot
    choose(slot == .base || !acceptsFolders ? .file : .fileOrFolder, for: slot)
  }

  /// Lets the user choose what `choice` allows for the field `slot`, and puts it there.
  func choose(_ choice: FileChoice, for slot: FileSlot) {
    guard let window, window.attachedSheet == nil else { return }
    let role = slot.title(
      hasBase: selection.hasBase, isFolder: selection.namesFolder(slot) || choice == .folder)
    Task {
      guard let url = await panels.chooseFile(choice, for: role, in: window) else { return }
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
      let places = places(for: urls, droppedOn: slot)
    else {
      dropTargets = [:]
      return []
    }
    var dropped = selection
    dropped.fill(places)
    dropTargets = Dictionary(
      uniqueKeysWithValues: places.keys.map { target in
        let role = dropped.title(of: target)
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
      let places = places(for: urls, droppedOn: slot)
    else { return false }
    fill(places)
    return true
  }

  /// Where `urls` go when they are dropped on `slot`, or anywhere for `nil`; a field that takes
  /// no file takes no drop.
  func places(for urls: [URL], droppedOn slot: FileSlot?) -> [FileSlot: URL]? {
    if let slot, fields[slot]?.isEnabled == false {
      return nil
    }
    return selection.places(for: urls, droppedOn: slot, acceptsFolders: acceptsFolders)
  }

  func dragDidEnd() {
    dropTargets = [:]
  }
}
