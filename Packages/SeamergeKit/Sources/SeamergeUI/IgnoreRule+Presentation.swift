import MergeModel

extension IgnoreRule.Problem {
  /// Why a rule with this problem leaves nothing out, as the warning in its row and the field
  /// that tries it say.
  var reason: String {
    switch self {
    case .invalidPattern:
      String(
        localized: "The pattern isn’t valid, so the rule ignores nothing.", bundle: .module,
        comment: "Settings: why an ignore rule takes no effect: its pattern does not compile.")
    case .matchesEmptyText:
      String(
        localized: "The pattern also matches empty text, so the rule ignores nothing.",
        bundle: .module,
        comment: "Settings: why an ignore rule takes no effect: its pattern matches empty text.")
    case .exceedsTimeLimit:
      String(
        localized: "The pattern takes too long to match, so the rule ignores nothing.",
        bundle: .module,
        comment: "Settings: why an ignore rule takes no effect: matching it takes too long.")
    }
  }
}

extension IgnoreRule {
  /// The title of the column of the names in Settings, which the name of a rule that has none
  /// shows as its placeholder.
  static var namePlaceholder: String {
    String(
      localized: "Name", bundle: .module,
      comment: "Settings: the column of the rule names, and the placeholder of a rule without one.")
  }

  /// The placeholder of a pattern that is still empty: the only place that names regular
  /// expressions, so that a newcomer knows what to type.
  static var patternPlaceholder: String {
    String(
      localized: "Regular Expression", bundle: .module,
      comment: "Settings: placeholder of the pattern of an ignore rule that has none yet.")
  }

  /// The name of a copy of the rule named `name`, which Duplicate makes.
  static func nameOfCopy(of name: String) -> String {
    String(
      localized: "\(name) copy", bundle: .module,
      comment: "Settings: the name of a copy of an ignore rule, such as Timestamps copy.")
  }
}
