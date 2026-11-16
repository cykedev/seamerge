import AppKit
import MergeModel
import Synchronization
import Testing

@testable import SeamergeUI

/// The ignore rules in the user defaults, under keys that count as an interface, and the rules
/// that come with the app.
@MainActor
struct IgnoreRuleSettingsTests {
  @Test func rulesOutlastALaunchUnderTheirKeys() {
    let defaults = UserDefaults.privateSuite()
    let settings = UserSettings(defaults: defaults)

    settings.enabledBuiltInIgnoreRules = [.uuids, .timestamps]
    settings.customIgnoreRules = [
      IgnoreRule(name: "Build date", pattern: #"\d{4}-\d{2}-\d{2}"#),
      IgnoreRule(name: "Revision", pattern: #"\$Id[^$]*\$"#, isEnabled: false),
    ]

    #expect(defaults.stringArray(forKey: "EnabledBuiltInIgnoreRules") == ["timestamps", "uuids"])
    let stored = defaults.array(forKey: "IgnoreRules") as? [[String: Any]]
    #expect(stored?.count == 2)
    #expect(stored?.first?["Name"] as? String == "Build date")
    #expect(stored?.first?["Pattern"] as? String == #"\d{4}-\d{2}-\d{2}"#)
    #expect(stored?.last?["Enabled"] as? Bool == false)
    let relaunched = UserSettings(defaults: defaults)
    #expect(relaunched.enabledBuiltInIgnoreRules == [.timestamps, .uuids])
    #expect(relaunched.customIgnoreRules == settings.customIgnoreRules)
  }

  @Test func rulesThatComeWithTheAppStandAtTheTopAndStartOff() {
    let settings = UserSettings.private()
    settings.customIgnoreRules = [IgnoreRule(name: "Own", pattern: "x+")]

    #expect(settings.ignoreRules.map(\.name) == ["Timestamps", "UUIDs", "Memory Addresses", "Own"])
    #expect(settings.ignoreRules.map(\.isEnabled) == [false, false, false, true])
  }

  @Test func entriesThatAreNoRuleAreLeftOut() {
    let defaults = UserDefaults.privateSuite()
    defaults.set(
      [
        ["Name": "No pattern"], "text", ["Pattern": "a+"],
        ["Name": "Off", "Pattern": "b", "Enabled": false],
      ],
      forKey: "IgnoreRules")
    defaults.set(["uuids", "sundays"], forKey: "EnabledBuiltInIgnoreRules")

    let settings = UserSettings(defaults: defaults)

    #expect(
      settings.customIgnoreRules == [
        IgnoreRule(name: "", pattern: "a+"),
        IgnoreRule(name: "Off", pattern: "b", isEnabled: false),
      ])
    #expect(settings.enabledBuiltInIgnoreRules == [.uuids])
  }

  @Test func changeOfTheRulesIsAnnouncedOnce() {
    let settings = UserSettings.private()
    let count = Mutex(0)
    let observer = NotificationCenter.default.addObserver(
      forName: UserSettings.ignoreRulesDidChangeNotification, object: settings, queue: nil
    ) { _ in count.withLock { $0 += 1 } }
    defer { NotificationCenter.default.removeObserver(observer) }

    settings.enabledBuiltInIgnoreRules = [.uuids]
    settings.enabledBuiltInIgnoreRules = [.uuids]
    settings.customIgnoreRules = [IgnoreRule(name: "Own", pattern: "x")]

    #expect(count.withLock { $0 } == 2)
  }
}

/// The patterns of the rules that come with the app: each matches its examples whole, and none
/// matches anything in the test files, which hold no such values.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct BuiltInIgnoreRuleTests {
  @Test(arguments: [
    (BuiltInIgnoreRule.timestamps, "2026-11-15 13:40:23.735+0100"),
    (.timestamps, "2026-11-15T13:40:23Z"),
    (.timestamps, "2026-11-15 13:40:23"),
    (.timestamps, "13:40:23"),
    (.timestamps, "9:05:00,125"),
    (.uuids, "8f14e45f-ceea-467f-a0e6-0b8f8b1d5c2a"),
    (.uuids, "8F14E45F-CEEA-467F-A0E6-0B8F8B1D5C2A"),
    (.memoryAddresses, "0x7ff8a1c03e40"),
    (.memoryAddresses, "0x600003a8c0"),
  ])
  func patternMatchesItsExampleWhole(rule: BuiltInIgnoreRule, example: String) async {
    let line = "at \(example) in main"
    let start = ("at " as NSString).length

    let trial = await rule.rule(isEnabled: true).trial(on: line, mode: .exact)

    #expect(trial == .matches([start..<start + (example as NSString).length]))
  }

  @Test(arguments: [
    (BuiltInIgnoreRule.timestamps, "Version 1.2.3 of 2026-11-15"),
    (.timestamps, "ratio 16:9"),
    (.uuids, "8f14e45f-ceea-467f-a0e6"),
    (.memoryAddresses, "0x7ff8a"),
    (.memoryAddresses, "0x7ff8a1c03e40g"),
  ])
  func patternLeavesLookalikesAlone(rule: BuiltInIgnoreRule, text: String) async {
    #expect(await rule.rule(isEnabled: true).trial(on: text, mode: .exact) == .matches([]))
  }

  @Test(arguments: BuiltInIgnoreRule.allCases)
  func patternIsValidAndMatchesNothingInTheTestFiles(rule: BuiltInIgnoreRule) async throws {
    let ignoreRule = rule.rule(isEnabled: true)
    #expect(ignoreRule.problem == nil)
    for (name, text) in try await Self.testFiles() {
      #expect(await ignoreRule.trial(on: text, mode: .exact) == .matches([]), "\(name)")
    }
  }

  /// The texts the tests compare and merge, by name: the files of every scenario of the test
  /// repository, the samples, and the examples of the repository.
  private static func testFiles() async throws -> [(String, String)] {
    var files: [(String, String)] = []
    for scenario in Scenario.merges {
      let (session, _) = try await scenario.load()
      for role in Role.allCases {
        guard let file = session.file(for: role) else { continue }
        files.append(("\(scenario.name) \(role)", String(decoding: file.bytes, as: UTF8.self)))
      }
    }
    files += [
      ("greeting old", SampleDiffs.greetingOld), ("greeting new", SampleDiffs.greetingNew),
      ("reformatted old", SampleDiffs.reformattedOld),
      ("reformatted new", SampleDiffs.reformattedNew),
      ("hello base", SampleMerges.helloWorldBase), ("hello A", SampleMerges.helloWorldA),
      ("hello B", SampleMerges.helloWorldB),
    ]
    let examples = URL(filePath: #filePath).deletingLastPathComponent()
      .appending(path: "../../../../Examples").standardized
    for side in ["A", "B", "Base"] {
      let folder = examples.appending(path: side)
      for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
        let text = try String(contentsOf: folder.appending(path: name), encoding: .utf8)
        files.append(("Examples/\(side)/\(name)", text))
      }
    }
    return files
  }
}
