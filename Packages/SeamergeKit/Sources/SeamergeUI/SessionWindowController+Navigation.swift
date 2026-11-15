import AppKit

extension SessionWindowController {
  /// Jumps to the next open conflict.
  @objc func selectNextConflict(_ sender: Any?) {
    jump(.nextOpenConflict)
  }

  /// Jumps to the previous open conflict.
  @objc func selectPreviousConflict(_ sender: Any?) {
    jump(.previousOpenConflict)
  }

  /// Jumps to the next change.
  @objc func selectNextChange(_ sender: Any?) {
    jump(.nextChange)
  }

  /// Jumps to the previous change.
  @objc func selectPreviousChange(_ sender: Any?) {
    jump(.previousChange)
  }

  /// Jumps to the first change.
  @objc func selectFirstChange(_ sender: Any?) {
    jump(.firstChange)
  }

  /// Jumps to the last change.
  @objc func selectLastChange(_ sender: Any?) {
    jump(.lastChange)
  }

  /// Jumps from the current block, an end of a move, to the other end.
  @objc func goToOtherEndOfMove(_ sender: Any?) {
    guard let block = presentation.otherEndOfMove else { return }
    presentation.jump(to: block)
  }

  private func jump(_ jump: BlockNavigation.Jump) {
    guard let block = presentation.navigation.target(of: jump) else { return }
    presentation.jump(to: block)
  }
}
