import Foundation
import MergeModel

/// An ignore rule that comes with the app, for text that changes on every run: Settings lists
/// it above the user's own rules, off at first, with its pattern in view but neither removable
/// nor changeable.
///
/// The patterns use plain groups, not `(?:`, since a group that starts with `(?` makes a
/// comparison try the pattern on every line on its own, which takes longer.
public enum BuiltInIgnoreRule: CaseIterable, Sendable {
  /// A time of day, with or without a date before it and a fraction of a second and a time zone
  /// after it, such as `2026-11-15 13:40:23.735+0100` or `13:40:23`.
  case timestamps

  /// A UUID: 32 hexadecimal digits in groups of 8, 4, 4, 4 and 12, in either case.
  case uuids

  /// A memory address: `0x` and at least six hexadecimal digits, such as `0x7ff8a1c03e40`.
  case memoryAddresses

  /// The name of the rule in Settings.
  public var name: String {
    switch self {
    case .timestamps:
      String(
        localized: "Timestamps", bundle: .module,
        comment: "Settings: an ignore rule that comes with the app, for dates and times of day.")
    case .uuids:
      String(
        localized: "UUIDs", bundle: .module,
        comment: "Settings: an ignore rule that comes with the app, for UUIDs.")
    case .memoryAddresses:
      String(
        localized: "Memory Addresses", bundle: .module,
        comment: "Settings: an ignore rule that comes with the app, for addresses such as 0x7ff8.")
    }
  }

  /// The regular expression.
  public var pattern: String {
    switch self {
    case .timestamps:
      #"\b(\d{4}-\d{2}-\d{2}[T ])?\d{1,2}:\d{2}:\d{2}([.,]\d+)?(Z|[+-]\d{2}:?\d{2})?\b"#
    case .uuids:
      #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#
    case .memoryAddresses:
      #"\b0x[0-9A-Fa-f]{6,}\b"#
    }
  }

  /// The rule, on or off as `isEnabled` says.
  func rule(isEnabled: Bool) -> IgnoreRule {
    IgnoreRule(name: name, pattern: pattern, isEnabled: isEnabled)
  }

  /// The name under which the user defaults keep whether the rule is on.
  var storedName: String {
    switch self {
    case .timestamps: "timestamps"
    case .uuids: "uuids"
    case .memoryAddresses: "memoryAddresses"
    }
  }
}
