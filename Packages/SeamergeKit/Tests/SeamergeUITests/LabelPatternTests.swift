import Testing

@testable import SeamergeUI

/// Filling the localized pattern of a label: by joining its pieces, or by formatting where a
/// translation numbers its placeholders.
struct LabelPatternTests {
  @Test func valuesTakeThePlaceholdersInTheirOrder() {
    let pattern = LabelPattern("Change in %@, line %lld")
    #expect(pattern.filled("A", "12") == "Change in A, line 12")
    #expect(LabelPattern("%@, line %lld").filled("From B", "3") == "From B, line 3")
    #expect(LabelPattern("Line %lld").filled("7") == "Line 7")
  }

  @Test func patternWithNumberedPlaceholdersPutsTheValuesWhereItSays() {
    let pattern = LabelPattern("Zeile %2$lld, Änderung in %1$@")
    #expect(pattern.filled("A", "12") == "Zeile 12, Änderung in A")
  }

  @Test func patternWithoutPlaceholdersStaysAsItIs() {
    #expect(LabelPattern("Edited by hand").filled() == "Edited by hand")
  }
}
