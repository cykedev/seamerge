import Foundation
import MergeModel

/// A field of the window Compare Files, in the order of the panes.
enum FileSlot: CaseIterable, Sendable {
  /// The older file of a comparison, or A of a merge.
  case left

  /// The common ancestor, which makes a merge of the files.
  case base

  /// The newer file of a comparison, or B of a merge.
  case right

  /// The word below the field: Left, Base (Optional) and Right until the base is chosen, then
  /// A, Base and B, which only mean something in a merge.
  func title(hasBase: Bool) -> String {
    switch (self, hasBase) {
    case (.left, false):
      String(localized: "Left", bundle: .module, comment: "Compare Files: the role of a field.")
    case (.right, false):
      String(localized: "Right", bundle: .module, comment: "Compare Files: the role of a field.")
    case (.base, false):
      String(
        localized: "Base (Optional)", bundle: .module,
        comment: "Compare Files: the role of the middle field, which may stay empty.")
    case (.left, true): Role.a.letter
    case (.base, true): Role.base.letter
    case (.right, true): Role.b.letter
    }
  }

  /// The role as VoiceOver says it, such as “Base, optional”.
  func accessibilityTitle(hasBase: Bool) -> String {
    guard self == .base, !hasBase else { return title(hasBase: hasBase) }
    return String(
      localized: "Base, optional", bundle: .module,
      comment: "VoiceOver: the role of the empty middle field of Compare Files.")
  }
}

/// The files in the fields of the window Compare Files, and the rules by which dropped files take
/// their places.
struct FileSelection: Equatable {
  private var files: [FileSlot: URL] = [:]

  /// The file in `slot`, if there is one.
  subscript(slot: FileSlot) -> URL? {
    get { files[slot] }
    set { files[slot] = newValue }
  }

  /// Whether the base is chosen, which makes a merge of the files.
  var hasBase: Bool { files[.base] != nil }

  /// Whether no field has a file.
  var isEmpty: Bool { files.isEmpty }

  /// The files in the fields, as the window opens them: two outer ones to compare, or all three
  /// to merge; `nil` otherwise.
  var comparison: FileComparison? {
    guard let left = files[.left], let right = files[.right] else { return nil }
    return FileComparison(left: left, base: files[.base], right: right)
  }

  /// Where `urls` go when they are dropped on the field `slot`, or anywhere on the window when
  /// `slot` is `nil`; `nil` if the window takes none of them.
  ///
  /// Three files fill all fields from left to right, two the outer ones. One file takes the field
  /// it is dropped on, or else the first free one of Left, Right and Base.
  func places(for urls: [URL], droppedOn slot: FileSlot?) -> [FileSlot: URL]? {
    switch urls.count {
    case 3:
      return [.left: urls[0], .base: urls[1], .right: urls[2]]
    case 2:
      return [.left: urls[0], .right: urls[1]]
    case 1:
      guard let target = slot ?? [.left, .right, .base].first(where: { files[$0] == nil }) else {
        return nil
      }
      return [target: urls[0]]
    default:
      return nil
    }
  }

  /// Puts the files of `places` in their fields.
  mutating func fill(_ places: [FileSlot: URL]) {
    files.merge(places) { $1 }
  }

  /// Swaps the files of two fields, whether or not both have one.
  mutating func swap(_ first: FileSlot, _ second: FileSlot) {
    (files[first], files[second]) = (files[second], files[first])
  }
}
