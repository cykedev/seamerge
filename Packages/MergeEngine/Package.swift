// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MergeEngine",
  platforms: [.macOS(.v15)],
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
    )
  ],
  swiftLanguageModes: [.v6],
  cxxLanguageStandard: .cxx17
)
