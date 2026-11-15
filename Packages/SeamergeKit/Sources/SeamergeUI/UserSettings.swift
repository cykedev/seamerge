import AppKit
import MergeModel
import Observation

/// The settings of the app and what its windows remember, kept in the user defaults; the only
/// place that reads or writes them for the windows.
///
/// The settings say how the code is drawn, how each new window starts, and which text the
/// comparisons of two files leave out. The text settings and the ignore rules take effect at once
/// in every open window; the others are where a new window starts, and the controls of a window
/// change only that window. What a window remembers for every window, its footer, sidebar, size
/// and split, is kept here as well, without a place in Settings.
///
/// Values that the user defaults hold out of range, or that name what no longer exists, read as
/// the standard.
@MainActor
@Observable
public final class UserSettings {
  /// Posted, with the settings as the object, after the font, its size, the line spacing or the
  /// tab width changed.
  static let textDidChangeNotification = Notification.Name(
    "app.eiden.seamerge.UserSettingsTextDidChange")

  /// Posted, with the settings as the object, after an ignore rule was added, removed or
  /// changed, or switched on or off.
  static let ignoreRulesDidChangeNotification = Notification.Name(
    "app.eiden.seamerge.UserSettingsIgnoreRulesDidChange")

  /// Posted, with the settings as the object, after the footer was hidden or shown.
  static let footerVisibilityDidChangeNotification = Notification.Name(
    "app.eiden.seamerge.UserSettingsFooterVisibilityDidChange")

  /// The user defaults that keep the values.
  @ObservationIgnored let defaults: UserDefaults

  /// The family of the font of the code, or `nil` for the monospaced system font.
  public var fontFamily: String? {
    didSet {
      guard fontFamily != oldValue else { return }
      defaults.set(fontFamily, forKey: Key.fontFamily)
      textDidChange()
    }
  }

  /// The size of the code, in points; a size beyond ``fontSizes`` becomes the nearest within.
  public var fontSize: CGFloat {
    get { storedFontSize }
    set {
      let size = min(max(newValue, Self.fontSizes.lowerBound), Self.fontSizes.upperBound)
      guard size != storedFontSize else { return }
      storedFontSize = size
      defaults.set(Double(size), forKey: Key.fontSize)
      textDidChange()
    }
  }

  /// How far apart the lines of the code are.
  public var lineSpacing: LineSpacing {
    didSet {
      guard lineSpacing != oldValue else { return }
      defaults.set(lineSpacing.storedName, forKey: Key.lineSpacing)
      textDidChange()
    }
  }

  /// The width of a tab, in characters; a width beyond ``tabWidths`` becomes the nearest within.
  public var tabWidth: Int {
    get { storedTabWidth }
    set {
      let width = min(max(newValue, Self.tabWidths.lowerBound), Self.tabWidths.upperBound)
      guard width != storedTabWidth else { return }
      storedTabWidth = width
      defaults.set(width, forKey: Key.tabWidth)
      textDidChange()
    }
  }

  private var storedFontSize: CGFloat
  private var storedTabWidth: Int

  /// How a new window compares lines.
  public var comparisonMode: ComparisonMode {
    didSet { defaults.set(comparisonMode.storedName, forKey: Key.comparisonMode) }
  }

  /// Whether a new merge window shows the pane of the base.
  public var showsBase: Bool {
    didSet { defaults.set(!showsBase, forKey: Key.hidesBase) }
  }

  /// Whether a new window colors its code by its syntax.
  public var highlightsSyntax: Bool {
    didSet { defaults.set(!highlightsSyntax, forKey: Key.highlightsNoSyntax) }
  }

  /// Whether a new window wraps long lines at the width of its panes.
  public var wrapsLines: Bool {
    didSet { defaults.set(wrapsLines, forKey: Key.wrapsLines) }
  }

  /// Whether a new window lines up the lines of its panes side by side, rather than showing
  /// the lines of each file as they are and connecting their changes with bands.
  public var alignsLines: Bool {
    didSet { defaults.set(!alignsLines, forKey: Key.connectsChanges) }
  }

  /// Whether a new window shows spaces, tabs and line endings.
  public var showsInvisibles: Bool {
    didSet { defaults.set(showsInvisibles, forKey: Key.showsInvisibles) }
  }

  /// Whether choosing the text of an open conflict goes on to the next open conflict.
  public var goesToNextConflict: Bool {
    didSet { defaults.set(!goesToNextConflict, forKey: Key.staysOnDecidedConflict) }
  }

  /// The rules that come with the app and are switched on.
  public var enabledBuiltInIgnoreRules: Set<BuiltInIgnoreRule> {
    didSet {
      guard enabledBuiltInIgnoreRules != oldValue else { return }
      defaults.set(
        BuiltInIgnoreRule.allCases.filter(enabledBuiltInIgnoreRules.contains).map(\.storedName),
        forKey: Key.enabledBuiltInIgnoreRules)
      ignoreRulesDidChange()
    }
  }

  /// The user's own ignore rules, in the order Settings lists them.
  public var customIgnoreRules: [IgnoreRule] {
    didSet {
      guard customIgnoreRules != oldValue else { return }
      defaults.set(
        customIgnoreRules.map { rule in
          [
            RuleKey.name: rule.name, RuleKey.pattern: rule.pattern,
            RuleKey.isEnabled: rule.isEnabled,
          ] as [String: Any]
        }, forKey: Key.customIgnoreRules)
      ignoreRulesDidChange()
    }
  }

  /// Every ignore rule as Settings lists it: those that come with the app, then the user's own.
  ///
  /// A comparison uses those that are switched on, while its window uses ignore rules.
  public var ignoreRules: [IgnoreRule] {
    BuiltInIgnoreRule.allCases.map { $0.rule(isEnabled: enabledBuiltInIgnoreRules.contains($0)) }
      + customIgnoreRules
  }

  /// Whether the windows show their footer, as the user last chose in any of them.
  var showsFooter: Bool {
    didSet {
      guard showsFooter != oldValue else { return }
      defaults.set(!showsFooter, forKey: Key.hidesFooter)
      NotificationCenter.default.post(
        name: Self.footerVisibilityDidChangeNotification, object: self)
    }
  }

  /// Whether a window of several files shows their list, as the user last chose in any of them.
  var showsFileList: Bool {
    didSet { defaults.set(!showsFileList, forKey: Key.hidesFileList) }
  }

  /// Whether a window of two folders lists their identical files too, as the user last chose in
  /// any of them.
  var showsIdenticalFiles: Bool {
    didSet { defaults.set(showsIdenticalFiles, forKey: Key.showsIdenticalFiles) }
  }

  /// The share of the height that the panes above the result took in the last merge window that
  /// closed, or `nil` before the first.
  var sourcesFraction: CGFloat? {
    get {
      let fraction = CGFloat(defaults.double(forKey: Key.sourcesFraction))
      return Self.sourcesFractions.contains(fraction) ? fraction : nil
    }
    set { defaults.set(newValue.map(Double.init), forKey: Key.sourcesFraction) }
  }

  /// Where the last window of `kind` that closed was and how large, as the window describes its
  /// frame, or `nil` before the first.
  func windowFrame(
    of kind: SessionWindowKind
  ) -> NSWindow.PersistableFrameDescriptor? {
    defaults.string(forKey: kind.frameKey)
  }

  /// Remembers `frame` as where the last window of `kind` was.
  func setWindowFrame(_ frame: NSWindow.PersistableFrameDescriptor, of kind: SessionWindowKind) {
    defaults.set(frame, forKey: kind.frameKey)
  }

  /// Reads the settings from `defaults` and keeps every change there.
  public init(defaults: UserDefaults) {
    self.defaults = defaults
    fontFamily = defaults.string(forKey: Key.fontFamily).flatMap { family in
      Self.monospacedFamilies.contains(family) ? family : nil
    }
    let sizeInDefaults = CGFloat(defaults.double(forKey: Key.fontSize))
    storedFontSize =
      Self.fontSizes.contains(sizeInDefaults) ? sizeInDefaults : Self.standardFontSize
    lineSpacing =
      defaults.string(forKey: Key.lineSpacing).flatMap(LineSpacing.init(storedName:)) ?? .standard
    let widthInDefaults = defaults.integer(forKey: Key.tabWidth)
    storedTabWidth =
      Self.tabWidths.contains(widthInDefaults) ? widthInDefaults : Self.standardTabWidth
    comparisonMode =
      defaults.string(forKey: Key.comparisonMode).flatMap(ComparisonMode.init(storedName:))
      ?? .windowDefault
    showsBase = !defaults.bool(forKey: Key.hidesBase)
    highlightsSyntax = !defaults.bool(forKey: Key.highlightsNoSyntax)
    wrapsLines = defaults.bool(forKey: Key.wrapsLines)
    alignsLines = !defaults.bool(forKey: Key.connectsChanges)
    showsInvisibles = defaults.bool(forKey: Key.showsInvisibles)
    goesToNextConflict = !defaults.bool(forKey: Key.staysOnDecidedConflict)
    showsFooter = !defaults.bool(forKey: Key.hidesFooter)
    showsFileList = !defaults.bool(forKey: Key.hidesFileList)
    showsIdenticalFiles = defaults.bool(forKey: Key.showsIdenticalFiles)
    let enabledNames = Set(defaults.stringArray(forKey: Key.enabledBuiltInIgnoreRules) ?? [])
    enabledBuiltInIgnoreRules = Set(
      BuiltInIgnoreRule.allCases.filter { enabledNames.contains($0.storedName) })
    customIgnoreRules = (defaults.array(forKey: Key.customIgnoreRules) ?? []).compactMap { entry in
      guard let entry = entry as? [String: Any], let pattern = entry[RuleKey.pattern] as? String
      else { return nil }
      return IgnoreRule(
        name: entry[RuleKey.name] as? String ?? "", pattern: pattern,
        isEnabled: entry[RuleKey.isEnabled] as? Bool ?? true)
    }
  }

  /// The font of the code at `size` points: the chosen family, or the monospaced system font.
  func codeFont(ofSize size: CGFloat) -> NSFont {
    fontFamily.flatMap {
      NSFontManager.shared.font(withFamily: $0, traits: [], weight: Self.regularWeight, size: size)
    } ?? .monospacedSystemFont(ofSize: size, weight: .regular)
  }

  /// The families of fonts of fixed width installed on the system, by name, without the
  /// monospaced system font, which Settings offers by itself.
  public static var monospacedFamilies: [String] {
    let families = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask)?.compactMap {
      NSFont(name: $0, size: standardFontSize)?.familyName
    }
    // Hidden families start with a period, as the system font does; SF Mono may also be
    // installed by name, which would offer the system font twice.
    return Set(families ?? []).filter { !$0.hasPrefix(".") && $0 != systemFontFamilyName }
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  /// The sizes the code can have, in points.
  public static let fontSizes: ClosedRange<CGFloat> = 9...24

  /// The widths a tab can have, in characters.
  public static let tabWidths: ClosedRange<Int> = 2...8

  /// The size of the code unless the user chooses another.
  static let standardFontSize: CGFloat = 13

  private static let standardTabWidth = 4

  /// The shares of the height above the result that a new window takes over; others leave too
  /// little of the panes above the result or of the result itself.
  private static let sourcesFractions: ClosedRange<CGFloat> = 0.1...0.9

  private static let systemFontFamilyName = "SF Mono"

  /// The weight of a regular font in the scale of the font manager.
  private static let regularWeight = 5

  private func ignoreRulesDidChange() {
    NotificationCenter.default.post(name: Self.ignoreRulesDidChangeNotification, object: self)
  }

  private func textDidChange() {
    NotificationCenter.default.post(name: Self.textDidChangeNotification, object: self)
  }

  /// The names of the values in the user defaults.
  ///
  /// Wrapping and syntax coloring keep the names under which the windows remembered them before
  /// they became settings, so that what a window remembered is where new windows start.
  private enum Key {
    static let fontFamily = "CodeFontFamily"
    static let fontSize = "CodeFontSize"
    static let lineSpacing = "LineSpacing"
    static let tabWidth = "TabWidth"
    static let comparisonMode = "ComparisonMode"
    static let hidesBase = "HidesBase"
    static let highlightsNoSyntax = "HighlightsNoSyntax"
    static let wrapsLines = "WrapsLines"
    static let connectsChanges = "ConnectsChanges"
    static let showsInvisibles = "ShowsInvisibles"
    static let staysOnDecidedConflict = "StaysOnDecidedConflict"
    static let hidesFooter = "HidesFooter"
    static let hidesFileList = "HidesFileList"
    static let showsIdenticalFiles = "ShowsIdenticalFiles"
    static let sourcesFraction = "SourcesFraction"
    static let enabledBuiltInIgnoreRules = "EnabledBuiltInIgnoreRules"
    static let customIgnoreRules = "IgnoreRules"
  }

  /// The names of the values of one of the user's own ignore rules, a dictionary in the array of
  /// ``Key/customIgnoreRules``.
  private enum RuleKey {
    static let name = "Name"
    static let pattern = "Pattern"
    static let isEnabled = "Enabled"
  }
}

/// The kinds of session window, each of which opens where the last one of its kind closed.
enum SessionWindowKind {
  /// A merge, with the result below its inputs.
  case merge

  /// A comparison of two files.
  case comparison

  /// A comparison of several files, with their list in a sidebar.
  case collection

  fileprivate var frameKey: String {
    switch self {
    case .merge: "MergeWindowFrame"
    case .comparison: "ComparisonWindowFrame"
    case .collection: "CollectionWindowFrame"
    }
  }
}

/// How far apart the lines of the code are, as a multiple of the font size.
public enum LineSpacing: Sendable, CaseIterable {
  /// Lines 1.3 times the font size apart.
  case compact

  /// Lines 1.5 times the font size apart.
  case standard

  /// Lines 1.7 times the font size apart.
  case spacious

  /// The height of a row as a multiple of the font size.
  var multiple: CGFloat {
    switch self {
    case .compact: 1.3
    case .standard: 1.5
    case .spacious: 1.7
    }
  }

  fileprivate var storedName: String {
    switch self {
    case .compact: "compact"
    case .standard: "standard"
    case .spacious: "spacious"
    }
  }

  fileprivate init?(storedName: String) {
    guard let spacing = Self.allCases.first(where: { $0.storedName == storedName }) else {
      return nil
    }
    self = spacing
  }
}

extension ComparisonMode {
  fileprivate var storedName: String {
    switch self {
    case .exact: "exact"
    case .ignoreLineEndings: "ignoreLineEndings"
    case .ignoreWhitespaceAmount: "ignoreWhitespaceAmount"
    case .ignoreAllWhitespace: "ignoreAllWhitespace"
    }
  }

  fileprivate init?(storedName: String) {
    guard let mode = Self.allCases.first(where: { $0.storedName == storedName }) else {
      return nil
    }
    self = mode
  }
}
