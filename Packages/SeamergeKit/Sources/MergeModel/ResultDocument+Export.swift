extension ResultDocument {
  /// The content of the merged file: the result text with conflict markers in place of the
  /// preview of every open conflict.
  ///
  /// The markers follow the `diff3` style of Git, with the own side first:
  ///
  /// ```
  /// <<<<<<< (label of B)
  /// (lines of B)
  /// ||||||| (label of the base)
  /// (lines of the base)
  /// =======
  /// (lines of A)
  /// >>>>>>> (label of A)
  /// ```
  ///
  /// Each marker starts a line, and each marker and each side ends with a line ending. Without
  /// hand edits, the content has the same bytes as the engine's merged text.
  ///
  /// - Parameter text: The result text, as long as the segments together.
  public func exportText(of text: String, labels: ConflictLabels) -> String {
    var content = ""
    for (index, segmentText) in split(text).enumerated() {
      if segments[index].state == .open {
        // Hand edits may have removed the line ending before the preview; a marker is only
        // recognized at the start of a line.
        if !content.isEmpty && !SegmentTexts.endsWithLineEnding(content) {
          content += texts.lineEnding
        }
        content += conflictMarkers(around: session.blocks[index], labels: labels)
      } else {
        content += segmentText
      }
    }
    return content
  }

  /// The three sides of a conflict between conflict markers.
  private func conflictMarkers(around block: Block, labels: ConflictLabels) -> String {
    texts.joined(
      [
        "<<<<<<< \(labels.b)\(texts.lineEnding)", texts.text(of: .b, in: block),
        "||||||| \(labels.base)\(texts.lineEnding)", texts.text(of: .base, in: block),
        "=======\(texts.lineEnding)", texts.text(of: .a, in: block),
        ">>>>>>> \(labels.a)\(texts.lineEnding)",
      ],
      followedByText: false)
  }
}
