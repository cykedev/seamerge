import AppKit

/// What a sheet of files or the welcome window does with files dragged onto a field or anywhere
/// else on it.
@MainActor
protocol FileDropDelegate: AnyObject {
  /// What a drop of `info` would do, as the pointer shows it; `slot` is the field under the
  /// pointer, or `nil` elsewhere on the window.
  func operation(forDrag info: any NSDraggingInfo, onto slot: FileSlot?) -> NSDragOperation

  /// Takes the drop of `info` and tells whether it did.
  func acceptDrop(_ info: any NSDraggingInfo, onto slot: FileSlot?) -> Bool

  /// The drag that `operation(forDrag:onto:)` was asked about left or ended.
  func dragDidEnd()
}

/// Reads the files of a drop.
enum FileDrop {
  /// The files and folders on `pasteboard`, each folder as a directory path, or `nil` if it
  /// holds none or something that is not there.
  @MainActor
  static func files(on pasteboard: NSPasteboard) -> [URL]? {
    let objects = pasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    guard let urls = objects as? [URL], !urls.isEmpty else { return nil }
    let entries = urls.map(entry(at:))
    return entries.contains(nil) ? nil : entries.compactMap(\.self)
  }

  /// `url` as the window takes it: a folder as a directory path, a file as it is; `nil` if
  /// nothing is there.
  static func entry(at url: URL) -> URL? {
    var isDirectory: ObjCBool = false
    let path = url.path(percentEncoded: false)
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
      return nil
    }
    return URL(filePath: path, directoryHint: isDirectory.boolValue ? .isDirectory : .notDirectory)
  }
}

/// The content of a sheet of files or of the welcome window, which takes files dropped anywhere
/// outside the fields.
final class FileDropView: NSView {
  /// Decides what a drop does; the view does not retain it.
  weak var delegate: (any FileDropDelegate)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    registerForDraggedTypes([.fileURL])
  }

  /// The view is made in code only.
  required init?(coder: NSCoder) {
    nil
  }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    delegate?.operation(forDrag: sender, onto: nil) ?? []
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    delegate?.operation(forDrag: sender, onto: nil) ?? []
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    delegate?.dragDidEnd()
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    delegate?.acceptDrop(sender, onto: nil) ?? false
  }

  override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
    delegate?.dragDidEnd()
  }
}
