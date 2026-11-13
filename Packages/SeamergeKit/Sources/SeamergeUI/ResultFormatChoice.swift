import AppKit
import MergeModel

/// A choice of how the result of a merge is written: its encoding or its line endings.
///
/// The submenus Result Encoding and Line Endings of the File menu and the pop-up menus of the
/// result header offer the same choices; the menu items send ``action`` with the choice as their
/// represented object, and the window carries it out and puts a checkmark at the one in effect.
public enum ResultFormatChoice: Hashable, Sendable {
  /// Writes the result in this encoding.
  case encoding(FileEncoding)

  /// Ends every line of the result this way.
  case lineEnding(ResultFormat.LineEnding)

  /// The choices of the encoding, in the order of their menu.
  public static let encodings: [ResultFormatChoice] = [
    .utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian,
    .windows1252, .isoLatin1, .macRoman,
  ].map(ResultFormatChoice.encoding)

  /// The choices of the line endings, in the order of their menu.
  public static let lineEndings = ResultFormat.LineEnding.allCases.map(
    ResultFormatChoice.lineEnding)

  /// The name of the choice in a menu.
  public var title: String {
    switch self {
    case .encoding(let encoding): encoding.name
    case .lineEnding(.lf): LineEndings.lf.name
    case .lineEnding(.crlf): LineEndings.crlf.name
    case .lineEnding(.cr): LineEndings.cr.name
    }
  }

  /// The title of the submenu of the encodings.
  public static var encodingMenuTitle: String {
    String(
      localized: "Result Encoding", bundle: .module,
      comment: "File menu: the submenu of the encodings the result can be saved in.")
  }

  /// The title of the submenu of the line endings.
  public static var lineEndingMenuTitle: String {
    String(
      localized: "Line Endings", bundle: .module,
      comment:
        "Line endings: the label in the details of a side, LF, CRLF or CR, and the submenu of the File menu that chooses those of the result."
    )
  }

  /// The help tag of the pop-up menu of the encodings in the result header.
  static var encodingHelp: String {
    String(
      localized: "Choose the encoding the result is saved in", bundle: .module,
      comment: "Help tag of the encoding in the result header.")
  }

  /// The help tag of the pop-up menu of the line endings in the result header.
  static var lineEndingHelp: String {
    String(
      localized: "Choose how the lines of the result end", bundle: .module,
      comment: "Help tag of the line endings in the result header.")
  }

  /// The action the menu items send along the responder chain.
  public static let action = #selector(SessionWindowController.chooseResultFormat(_:))

  /// A menu item that sends the choice.
  public func menuItem() -> NSMenuItem {
    let item = NSMenuItem(title: title, action: Self.action, keyEquivalent: "")
    item.representedObject = self
    return item
  }

  /// The choice that `item` sends, if it sends one.
  init?(item: Any?) {
    guard let choice = (item as? NSMenuItem)?.representedObject as? ResultFormatChoice else {
      return nil
    }
    self = choice
  }
}
