import Foundation
import MergeModel

@testable import SeamergeUI

extension SessionWindowController {
  /// Resolves every open conflict with the text of `roles`, as if the user had chosen it.
  ///
  /// - Precondition: The window shows a merge.
  func resolveOpenConflicts(with roles: [Role]) {
    guard let result = presentation.result else {
      preconditionFailure("Only a merge has conflicts to resolve")
    }
    var document = result.document
    let plan = document.planResolvingOpenConflicts(with: roles)
    var text = result.text
    var replaced: [String] = []
    for replacement in plan.replacements {
      let units = Array(text.utf16)
      replaced.append(String(decoding: units[replacement.range], as: UTF16.self))
      text =
        String(decoding: units[..<replacement.range.lowerBound], as: UTF16.self)
        + replacement.text
        + String(decoding: units[replacement.range.upperBound...], as: UTF16.self)
    }
    _ = document.apply(plan, replacedTexts: replaced)
    presentation.show(.merge(ResultState(document: document, text: text)))
    stateDidChange()
  }
}
