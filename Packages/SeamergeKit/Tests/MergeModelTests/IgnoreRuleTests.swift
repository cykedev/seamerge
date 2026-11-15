import Foundation
import MergeModel
import Testing

struct IgnoreRuleTests {
  static let date = IgnoreRule(name: "Build date", pattern: #"\d{4}-\d{2}-\d{2}"#)

  @Test func patternThatCompilesAndNeedsTextIsValid() {
    #expect(Self.date.problem == nil)
    #expect(IgnoreRule(name: "Revision", pattern: #"\$Id:[^$]*\$"#).problem == nil)
  }

  @Test(arguments: ["", "(", "[a-", "a{2,1}", #"\"#, "(?<name"])
  func patternThatDoesNotCompileIsInvalid(pattern: String) {
    #expect(IgnoreRule(name: "Broken", pattern: pattern).problem == .invalidPattern)
  }

  @Test(arguments: [".*", #"\s*"#, "^", "$", "x?", "(abc)*"])
  func patternThatMatchesEmptyTextIsInvalid(pattern: String) {
    #expect(IgnoreRule(name: "Everything", pattern: pattern).problem == .matchesEmptyText)
  }
}
