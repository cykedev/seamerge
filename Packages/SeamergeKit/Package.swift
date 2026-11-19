// swift-tools-version: 6.2

import PackageDescription

let swiftSettings: [SwiftSetting] = [.treatAllWarnings(as: .error)]

/// The modules of the app and the modules each of them may import.
///
/// A module that is not listed as a dependency cannot be imported, so this
/// table is the module graph. Arrows only point downwards: the user interface
/// knows the model, the model never knows the user interface.
let modules: [(name: String, dependencies: [Target.Dependency])] = [
  ("TextBasics", []),
  ("TextIO", ["TextBasics"]),
  (
    "MergeModel",
    [.product(name: "MergeEngine", package: "MergeEngine"), "TextBasics", "TextIO"]
  ),
  ("GitSupport", []),
  ("SessionIPC", []),
  ("SeamergeCLI", ["SessionIPC", "GitSupport"]),
  ("SyntaxKit", []),
  ("PaneKit", ["TextBasics"]),
  ("SeamergeUI", ["PaneKit", "MergeModel", "SyntaxKit", "GitSupport", "TextBasics"]),
]

let package = Package(
  name: "SeamergeKit",
  defaultLocalization: "en",
  platforms: [.macOS("27.0")],
  products: [
    // Only the modules the app and the command-line tool link directly.
    .library(name: "SeamergeUI", targets: ["SeamergeUI"]),
    .library(name: "MergeModel", targets: ["MergeModel"]),
    .library(name: "SeamergeCLI", targets: ["SeamergeCLI"]),
    .library(name: "SessionIPC", targets: ["SessionIPC"]),
    .library(name: "GitSupport", targets: ["GitSupport"]),
  ],
  dependencies: [
    .package(path: "../MergeEngine")
  ],
  targets: modules.flatMap { module in
    [
      .target(
        name: module.name,
        dependencies: module.dependencies,
        swiftSettings: swiftSettings
      ),
      // A test may use what its module uses, such as the types of the module's interface.
      .testTarget(
        name: "\(module.name)Tests",
        dependencies: [.target(name: module.name)] + module.dependencies,
        swiftSettings: swiftSettings
      ),
    ]
  },
  swiftLanguageModes: [.v6]
)
