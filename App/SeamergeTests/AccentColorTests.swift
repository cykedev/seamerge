import AppKit
import Testing

/// The accent color the app brings, which the system uses only while the user chooses
/// Multicolor as the accent color.
@MainActor
@Suite struct AccentColorTests {
  /// The values of the color in the asset catalog, by the appearance they are for.
  private static let expected: [Variant: String] = [
    Variant(dark: false, increasedContrast: false): "0A62CC",
    Variant(dark: false, increasedContrast: true): "0047A3",
    Variant(dark: true, increasedContrast: false): "1F6FE0",
    Variant(dark: true, increasedContrast: true): "2672E4",
  ]

  @Test func appNamesItsAccentColor() throws {
    let app = Bundle(for: AppDelegate.self).bundleURL.deletingLastPathComponent()
      .appending(path: "Seamerge.app")
    let bundle = try #require(Bundle(url: app))
    #expect(bundle.infoDictionary?["NSAccentColorName"] as? String == "AccentColor")

    let color = try #require(NSColor(named: "AccentColor", bundle: bundle))
    for (name, dark) in [(NSAppearance.Name.aqua, false), (.darkAqua, true)] {
      let appearance = try #require(NSAppearance(named: name))
      let expected = try #require(Self.expected[Variant(dark: dark, increasedContrast: false)])
      #expect(try Self.hex(of: color, in: appearance) == expected, "\(name.rawValue)")
    }
  }

  /// White reads on every value, and every value stands out from the window.
  ///
  /// White, the title of a default button and of a selected line, reaches 4.5 : 1; every value
  /// stands out from the window as a control does, at 3 : 1, and a value for increased contrast
  /// at least as much as the plain one. The values are read from the asset catalog, since an
  /// appearance with increased contrast cannot be made by name, and measured against the plain
  /// window.
  @Test func whiteReadsOnEveryValueAndEveryValueStandsOutFromTheWindow() throws {
    let catalog = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "Seamerge/Assets.xcassets/AccentColor.colorset/Contents.json")
    let values = try Self.values(in: Data(contentsOf: catalog))
    #expect(values == Self.expected)

    for (variant, value) in values {
      let appearance = try #require(NSAppearance(named: variant.dark ? .darkAqua : .aqua))
      let window = try Self.hex(of: .windowBackgroundColor, in: appearance)
      let onWindow = Self.contrastRatio(value, window)
      let white = Self.contrastRatio("FFFFFF", value)
      #expect(white >= 4.5, "white on \(variant): \(String(format: "%.2f", white))")
      #expect(onWindow >= 3, "\(variant) on the window: \(String(format: "%.2f", onWindow))")
      if variant.increasedContrast {
        let plain = try #require(values[Variant(dark: variant.dark, increasedContrast: false)])
        #expect(onWindow >= Self.contrastRatio(plain, window), "\(variant)")
      }
    }
  }

  /// An appearance a value of the color is for.
  private struct Variant: Hashable, CustomStringConvertible {
    var dark: Bool
    var increasedContrast: Bool

    var description: String {
      (dark ? "dark" : "light") + (increasedContrast ? ", increased contrast" : "")
    }
  }

  private static func values(in data: Data) throws -> [Variant: String] {
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let colors = try #require(object?["colors"] as? [[String: Any]])
    var values: [Variant: String] = [:]
    for entry in colors {
      let appearances = entry["appearances"] as? [[String: String]] ?? []
      let variant = Variant(
        dark: appearances.contains { $0["appearance"] == "luminosity" && $0["value"] == "dark" },
        increasedContrast: appearances.contains {
          $0["appearance"] == "contrast" && $0["value"] == "high"
        })
      let color = try #require(entry["color"] as? [String: Any])
      #expect(color["color-space"] as? String == "srgb")
      let components = try #require(color["components"] as? [String: String])
      values[variant] = try ["red", "green", "blue"].map { key in
        try #require(components[key]?.dropFirst(2)).uppercased()
      }.joined()
    }
    return values
  }

  private static func hex(of color: NSColor, in appearance: NSAppearance) throws -> String {
    var resolved: NSColor?
    appearance.performAsCurrentDrawingAppearance {
      resolved = color.usingColorSpace(.sRGB)
    }
    let srgb = try #require(resolved)
    return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
      .map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
  }

  private static func contrastRatio(_ first: String, _ second: String) -> Double {
    let (lighter, darker) = (luminance(first), luminance(second))
    return (max(lighter, darker) + 0.05) / (min(lighter, darker) + 0.05)
  }

  private static func luminance(_ hex: String) -> Double {
    let value = Int(hex, radix: 16) ?? 0
    let channels = [16, 8, 0].map { shift -> Double in
      let channel = Double((value >> shift) & 0xFF) / 255
      return channel <= 0.040_45 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
  }
}
