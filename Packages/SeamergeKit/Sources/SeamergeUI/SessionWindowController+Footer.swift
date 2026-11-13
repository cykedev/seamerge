import AppKit

extension SessionWindowController {
  /// Shows in the footer the comparison mode and the state of each toggle as they are now.
  func updateFooter() {
    let footer = content.footer
    guard footer.superview != nil, !footer.isHidden else { return }
    let mode =
      SessionFooterView.modeCommands.first { $0.comparisonMode == comparisonOptions.mode }
      ?? .compareExactly
    var toggles: [FooterToggle: SessionFooterView.State.Toggle] = [:]
    for toggle in footer.toggles {
      let state = footerState(of: toggle)
      toggles[toggle] = SessionFooterView.State.Toggle(
        state: state, isEnabled: canPerform(toggle.command(in: state)))
    }
    footer.show(
      SessionFooterView.State(
        mode: mode, canChangeMode: canPerform(.compareExactly), toggles: toggles))
  }

  /// The state of `toggle`, as the main menu shows it with a checkmark or a title.
  private func footerState(of toggle: FooterToggle) -> NSControl.StateValue {
    switch toggle {
    case .invisibles: isSwitchedOn(.toggleInvisibles) ? .on : .off
    case .scrollSynchronization: isSwitchedOn(.toggleScrollSynchronization) ? .on : .off
    case .base: layout.showsBase ? .on : .off
    case .collapsedLines:
      switch (canPerform(.showAllLines), canPerform(.collapseUnchangedLines)) {
      case (true, true): .mixed
      case (true, false): .on
      default: .off
      }
    }
  }
}
