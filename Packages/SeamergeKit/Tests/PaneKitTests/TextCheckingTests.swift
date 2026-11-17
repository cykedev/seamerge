import AppKit
import PaneKit
import Testing

/// Checks that a pane, read-only or editable, checks nothing in its text and so gives the text
/// checking controller no text to check, which it asks for after every layout of the viewport.
@MainActor
@Suite struct TextCheckingTests {
  @Test(arguments: [false, true])
  func paneChecksNothing(editable: Bool) throws {
    let pane = PaneView()
    let recorder = EditRecorder()
    if editable { pane.editingDelegate = recorder }
    pane.content = CodeRows.content(count: 50, length: 40, blocks: [])
    let view = pane.documentView
    #expect(view.isEditable == editable)
    #expect(!view.isContinuousSpellCheckingEnabled)
    #expect(!view.isGrammarCheckingEnabled)
    #expect(!view.isAutomaticSpellingCorrectionEnabled)
    #expect(!view.isAutomaticQuoteSubstitutionEnabled)
    #expect(!view.isAutomaticDashSubstitutionEnabled)
    #expect(!view.isAutomaticTextReplacementEnabled)
    #expect(!view.isAutomaticLinkDetectionEnabled)
    #expect(!view.isAutomaticDataDetectionEnabled)
    #expect(!view.isAutomaticTextCompletionEnabled)
    #expect(view.inlinePredictionType == .no)
    #expect(view.mathExpressionCompletionType == .no)
    #expect(view.writingToolsBehavior == .none)
    let client = try #require(view as? any NSTextCheckingClient)
    var actualRange = NSRange(location: NSNotFound, length: 0)
    let text = client.annotatedSubstring(
      forProposedRange: NSRange(location: 0, length: 200), actualRange: &actualRange)
    #expect(text == nil)
  }
}
