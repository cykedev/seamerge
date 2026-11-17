import AppKit

/// The fields of the sheet of files on `window` from left to right, as VoiceOver names them and
/// their files.
@MainActor
func fileFields(in window: NSWindow) -> [(label: String?, value: String?)] {
  func find(in view: NSView) -> [NSView] {
    String(describing: type(of: view)) == "FileField" ? [view] : view.subviews.flatMap(find)
  }
  return (window.attachedSheet?.contentView.map(find) ?? []).map {
    ($0.accessibilityLabel(), $0.accessibilityValue() as? String)
  }
}

/// What VoiceOver says for a field that holds `url`: its name and its folder, with the home
/// folder as a tilde.
func fileFieldValue(of url: URL) -> String {
  let folder = (url.deletingLastPathComponent().path(percentEncoded: false) as NSString)
    .abbreviatingWithTildeInPath
  return "\(url.lastPathComponent), in \(folder)"
}

/// The texts of the labels in `window` and in the sheet on it.
@MainActor
func labelTexts(in window: NSWindow) -> [String] {
  func find(in view: NSView) -> [String] {
    ((view as? NSTextField).map { [$0.stringValue] } ?? []) + view.subviews.flatMap(find)
  }
  return [window.contentView, window.attachedSheet?.contentView].compactMap(\.self).flatMap(find)
}
