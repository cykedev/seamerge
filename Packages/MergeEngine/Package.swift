// swift-tools-version: 6.2

import PackageDescription

// For the Swift targets only: the vendored Perforce code is compiled unchanged
// and has warnings of its own. Imports are internal unless marked otherwise,
// and a file uses only the members of the modules it imports itself.
let swiftSettings: [SwiftSetting] = [
  .treatAllWarnings(as: .error),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
  name: "MergeEngine",
  platforms: [.macOS("27.0")],
  products: [
    .library(name: "MergeEngine", targets: ["MergeEngine"]),
    .executable(name: "mergecli", targets: ["mergecli"]),
  ],
  targets: [
    // The Perforce diff/merge engine (Vendor/Perforce), the adapter that
    // replaces the Perforce interfaces it depends on (Adapter), and the C
    // interface over both (Bridge, include). See VENDORING.md.
    .target(
      name: "CMergeEngine",
      exclude: ["Vendor/Perforce/LICENSE"],
      cxxSettings: [
        .headerSearchPath("Adapter"),
        .headerSearchPath("Vendor/Perforce/diff"),
        .headerSearchPath("Vendor/Perforce/sys"),
        .define("OS_MACOSX"),
        .define("OS_DARWIN"),
      ]
    ),
    .target(
      name: "MergeEngine",
      dependencies: ["CMergeEngine"],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "mergecli",
      dependencies: ["MergeEngine"],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "MergeEngineTests",
      dependencies: ["MergeEngine"],
      resources: [.copy("Fixtures")],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "mergecliTests",
      dependencies: ["mergecli"],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6],
  cxxLanguageStandard: .cxx17
)
