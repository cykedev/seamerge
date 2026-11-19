// Writes string catalogs as Xcode writes them, so that a catalog edited by hand or by a tool
// does not change again, line by line, the next time Xcode opens it: two spaces of indentation,
// a space on both sides of each colon, the keys of every object in the order of
// `localizedStandardCompare(_:)`, no escaped slashes and no newline at the end.
//
// Usage: swift Scripts/Support/FormatStringCatalog.swift [--check] <catalog>...
//
// Rewrites each catalog that is not in this form; with --check, changes nothing, names each such
// catalog and exits with 1.

import Foundation

enum Format {
  static func text(of value: Any, indent: String = "") -> String {
    let inner = indent + "  "
    switch value {
    case let object as [String: Any]:
      if object.isEmpty { return "{\n\n\(indent)}" }
      let members = object.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        .map { "\(inner)\(string($0.key)) : \(text(of: $0.value, indent: inner))" }
      return "{\n" + members.joined(separator: ",\n") + "\n\(indent)}"
    case let array as [Any]:
      if array.isEmpty { return "[\n\n\(indent)]" }
      let elements = array.map { inner + text(of: $0, indent: inner) }
      return "[\n" + elements.joined(separator: ",\n") + "\n\(indent)]"
    case let string as String:
      return self.string(string)
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
      return number.stringValue
    default:
      return "null"
    }
  }

  static func string(_ string: String) -> String {
    var result = "\""
    for scalar in string.unicodeScalars {
      switch scalar {
      case "\"": result += "\\\""
      case "\\": result += "\\\\"
      case "\n": result += "\\n"
      case "\r": result += "\\r"
      case "\t": result += "\\t"
      case _ where scalar.value < 0x20: result += String(format: "\\u%04x", scalar.value)
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result + "\""
  }
}

var arguments = Array(CommandLine.arguments.dropFirst())
let checks = arguments.first == "--check"
if checks { arguments.removeFirst() }
guard !arguments.isEmpty else {
  let usage = "usage: FormatStringCatalog.swift [--check] <catalog>...\n"
  FileHandle.standardError.write(Data(usage.utf8))
  exit(2)
}

var unformatted = false
for path in arguments {
  let url = URL(fileURLWithPath: path)
  do {
    let data = try Data(contentsOf: url)
    let catalog = try JSONSerialization.jsonObject(with: data)
    let formatted = Data(Format.text(of: catalog).utf8)
    guard formatted != data else { continue }
    if checks {
      print("\(path) is not in the form Xcode writes; run Scripts/format-strings.sh")
      unformatted = true
    } else {
      try formatted.write(to: url, options: .atomic)
      print("formatted \(path)")
    }
  } catch {
    print("\(path): \(error.localizedDescription)")
    unformatted = true
  }
}
exit(unformatted ? 1 : 0)
