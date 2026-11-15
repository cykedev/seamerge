import AppKit

/// The field below the ignore rules in which the user pastes text to try the selected rule:
/// what the rule leaves out is marked as Show Ignored Changes marks it in a window.
///
/// The text is not kept; the marks are drawn over it without changing it.
@MainActor
final class RuleTrialField: NSView, NSTextViewDelegate {
  /// Called after the user changed the text.
  var onTextChange: (() -> Void)?

  /// The text the user typed or pasted.
  var text: String {
    get { textView.string }
    set {
      textView.string = newValue
      textDidChange()
    }
  }

  /// The marked characters, as UTF-16 offsets in ``text``, in text order.
  private(set) var markedRanges: [Range<Int>] = []

  /// The color behind the marked characters.
  var markColor: NSColor {
    didSet { mark(markedRanges) }
  }

  let textView: NSTextView
  private let scrollView: NSScrollView
  private let placeholder: NSTextField

  /// Creates the field named `label` for VoiceOver, with its text in `font` and marks in
  /// `markColor`.
  init(label: String, font: NSFont, markColor: NSColor) {
    self.markColor = markColor
    scrollView = NSTextView.scrollableTextView()
    guard let textView = scrollView.documentView as? NSTextView else {
      preconditionFailure("A scrollable text view holds a text view")
    }
    self.textView = textView
    let placeholderText = String(
      localized: "Paste text to try the selected rule", bundle: .module,
      comment: "Settings: placeholder of the field in which an ignore rule is tried.")
    placeholder = NSTextField(labelWithString: placeholderText)
    super.init(frame: .zero)
    scrollView.borderType = .lineBorder
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    textView.font = font
    textView.textContainerInset = NSSize(
      width: WindowMetrics.ruleTrialInset, height: WindowMetrics.ruleTrialInset)
    textView.isRichText = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = false
    textView.delegate = self
    textView.setAccessibilityLabel(label)
    textView.setAccessibilityPlaceholderValue(placeholderText)
    placeholder.font = font
    placeholder.textColor = .placeholderTextColor
    placeholder.translatesAutoresizingMaskIntoConstraints = false
    // The text view reads the placeholder out itself.
    placeholder.setAccessibilityElement(false)
    addSubview(scrollView)
    addSubview(placeholder)
    let textInset =
      WindowMetrics.ruleTrialInset + (textView.textContainer?.lineFragmentPadding ?? 0)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
      placeholder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textInset + 1),
      placeholder.topAnchor.constraint(
        equalTo: topAnchor, constant: WindowMetrics.ruleTrialInset + 1),
    ])
  }

  /// Rule trial fields are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  /// Marks `ranges`, UTF-16 offsets in ``text``, and nothing else.
  func mark(_ ranges: [Range<Int>]) {
    markedRanges = ranges
    guard let layoutManager = textView.textLayoutManager,
      let storage = layoutManager.textContentManager
    else { return }
    layoutManager.removeRenderingAttribute(
      .backgroundColor, for: layoutManager.documentRange)
    let length = (textView.string as NSString).length
    for range in ranges where range.upperBound <= length {
      guard
        let start = storage.location(storage.documentRange.location, offsetBy: range.lowerBound),
        let end = storage.location(start, offsetBy: range.count),
        let textRange = NSTextRange(location: start, end: end)
      else { continue }
      layoutManager.addRenderingAttribute(.backgroundColor, value: markColor, for: textRange)
    }
  }

  func textDidChange(_ notification: Notification) {
    textDidChange()
  }

  private func textDidChange() {
    placeholder.isHidden = !textView.string.isEmpty
    // Marks belong to the text they were found in.
    mark([])
    onTextChange?()
  }
}
