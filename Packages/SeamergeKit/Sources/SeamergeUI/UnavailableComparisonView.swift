import AppKit

/// What a comparison window shows in place of the lines of files it cannot compare: a title that
/// says so and a message with the reason and the next step, centered on the background of text.
@MainActor
final class UnavailableComparisonView: NSView {
  /// Creates the view with `title` above `message`, if there is one.
  init(title: String, message: String?) {
    super.init(frame: .zero)
    let titleField = NSTextField(wrappingLabelWithString: title)
    titleField.font = .preferredFont(forTextStyle: .title3)
    var fields = [titleField]
    if let message {
      let messageField = NSTextField(wrappingLabelWithString: message)
      messageField.font = .preferredFont(forTextStyle: .body)
      fields.append(messageField)
    }
    for field in fields {
      field.alignment = .center
      field.textColor = .labelColor
      field.isSelectable = false
    }
    let stack = NSStackView(views: fields)
    stack.orientation = .vertical
    stack.spacing = WindowMetrics.unavailableSpacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      stack.widthAnchor.constraint(lessThanOrEqualToConstant: WindowMetrics.unavailableWidth),
      stack.leadingAnchor.constraint(
        greaterThanOrEqualTo: leadingAnchor, constant: WindowMetrics.unavailableInset),
      stack.trailingAnchor.constraint(
        lessThanOrEqualTo: trailingAnchor, constant: -WindowMetrics.unavailableInset),
    ])
  }

  /// Such views are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
  }
}
