import AppKit

/// The content storage of a pane's text view, which steps over the text that collapsed runs hide
/// in one go when TextKit enumerates the paragraphs.
///
/// The delegate leaves out each hidden paragraph as well, but TextKit would still visit every one
/// of them, and it enumerates from the end of the text to estimate its size after each layout: in
/// a long file with runs collapsed, that is tens of thousands of paragraphs each time. The storage
/// enumerates the paragraphs between hidden ranges as the storage does without them and starts
/// again behind each range, so that the delegate is only asked about paragraphs it shows.
final class PaneContentStorage: NSTextContentStorage {
  /// The UTF-16 ranges of the text that is left out, sorted and apart; each starts and ends at
  /// the start of a paragraph or at the end of the text.
  var hiddenRanges: [Range<Int>] = []

  override func enumerateTextElements(
    from textLocation: (any NSTextLocation)?, options: NSTextContentManager.EnumerationOptions = [],
    using block: (NSTextElement) -> Bool
  ) -> (any NSTextLocation)? {
    guard !hiddenRanges.isEmpty else {
      return super.enumerateTextElements(from: textLocation, options: options, using: block)
    }
    guard options.contains(.reverse) else {
      return enumerateForward(
        from: textLocation.map(offset(of:)) ?? 0, options: options, using: block)
    }
    // Without a location, a backward enumeration finds nothing, as the storage's own does.
    guard let textLocation else { return documentRange.location }
    return enumerateBackward(from: offset(of: textLocation), options: options, using: block)
  }

  /// Enumerates the shown paragraphs from the one that contains `start` to the end of the text.
  ///
  /// Returns the end of the paragraph that `block` stopped at, or the end of the text.
  private func enumerateForward(
    from start: Int, options: NSTextContentManager.EnumerationOptions,
    using block: (NSTextElement) -> Bool
  ) -> (any NSTextLocation)? {
    var start = start
    var index = hiddenRanges.partitioningIndex { $0.upperBound > start }
    while true {
      if index < hiddenRanges.count, hiddenRanges[index].lowerBound <= start {
        // The paragraph that contains `start` and those after it up to the end of the range
        // are hidden.
        start = hiddenRanges[index].upperBound
        index += 1
        continue
      }
      guard start < textLength, let location = location(atOffset: start) else {
        return documentRange.endLocation
      }
      let end = index < hiddenRanges.count ? hiddenRanges[index].lowerBound : nil
      var isStopped = false
      let result = super.enumerateTextElements(from: location, options: options) { element in
        guard block(element) else {
          isStopped = true
          return false
        }
        return end.map { offset(ofEndOf: element) < $0 } ?? true
      }
      guard !isStopped, let end else { return result }
      start = end
    }
  }

  /// Enumerates the shown paragraphs backward from the one that contains `end`, or the one
  /// before it if a paragraph starts at `end`, to the start of the text.
  ///
  /// Returns the start of the paragraph that `block` stopped at, or the start of the text.
  private func enumerateBackward(
    from end: Int, options: NSTextContentManager.EnumerationOptions,
    using block: (NSTextElement) -> Bool
  ) -> (any NSTextLocation)? {
    var end = end
    var index = hiddenRanges.partitioningIndex { $0.lowerBound >= end } - 1
    while true {
      if index >= 0, hiddenRanges[index].upperBound >= end {
        // The paragraph before `end`, or the one that contains it, and those before it down to
        // the start of the range are hidden.
        end = hiddenRanges[index].lowerBound
        index -= 1
        continue
      }
      guard end > 0, let location = location(atOffset: end) else {
        return documentRange.location
      }
      let start = index >= 0 ? hiddenRanges[index].upperBound : nil
      var isStopped = false
      let result = super.enumerateTextElements(from: location, options: options) { element in
        guard block(element) else {
          isStopped = true
          return false
        }
        return start.map { offset(ofStartOf: element) > $0 } ?? true
      }
      guard !isStopped, let start else { return result }
      end = start
    }
  }

  private var textLength: Int {
    offset(from: documentRange.location, to: documentRange.endLocation)
  }

  private func offset(of location: any NSTextLocation) -> Int {
    offset(from: documentRange.location, to: location)
  }

  private func location(atOffset offset: Int) -> (any NSTextLocation)? {
    location(documentRange.location, offsetBy: offset)
  }

  private func offset(ofStartOf element: NSTextElement) -> Int {
    element.elementRange.map { offset(of: $0.location) } ?? 0
  }

  private func offset(ofEndOf element: NSTextElement) -> Int {
    element.elementRange.map { offset(of: $0.endLocation) } ?? textLength
  }
}
