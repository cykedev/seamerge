import SyntaxKit
import Testing

struct LanguageDetectionTests {
  @Test(arguments: [
    ("Main.SWIFT", "Swift"), ("View.h", "Objective-C"), ("main.cc", "C++"),
    ("App.tsx", "TypeScript"), ("App.jsx", "JavaScript"), ("Info.plist", "XML"),
    ("Localizable.xcstrings", "JSON"), ("docker-compose.yml", "YAML"),
    ("/path/to/archive.tar.toml", "TOML"),
  ])
  func fileExtensionDecidesTheLanguage(fileName: String, language: String) {
    #expect(LanguageDescription(fileName: fileName).name == language)
  }

  @Test(arguments: [
    ("Gemfile", "Ruby"), ("project/Podfile", "Ruby"), (".zshrc", "Shell"),
    ("Cargo.lock", "TOML"),
  ])
  func wholeFileNameDecidesTheLanguage(fileName: String, language: String) {
    #expect(LanguageDescription(fileName: fileName).name == language)
  }

  @Test(arguments: [
    ("#!/bin/bash", "Shell"), ("#!/bin/sh -e", "Shell"),
    ("#!/usr/bin/env python3.12", "Python"), ("#!/usr/bin/env -S node --no-warnings", "JavaScript"),
    ("#!/usr/bin/env RUBYOPT=-w ruby", "Ruby"), ("#!/usr/bin/swift", "Swift"),
    ("#! /usr/bin/env zsh\r\n", "Shell"),
  ])
  func interpreterOfTheFirstLineDecidesForAFileWithoutExtension(
    firstLine: String, language: String
  ) {
    #expect(LanguageDescription(fileName: "script", firstLine: firstLine).name == language)
  }

  @Test func fileExtensionWinsOverTheFirstLine() {
    #expect(LanguageDescription(fileName: "tool.rb", firstLine: "#!/bin/sh").name == "Ruby")
  }

  @Test(arguments: [
    ("README", ""), ("notes.unknown", ""), (".gitignore", ""), ("script", "#!/usr/bin/perl"),
    ("script", "#!"), ("script", "echo hi"), ("", ""),
  ])
  func unrecognizedFileIsPlainText(fileName: String, firstLine: String) {
    #expect(LanguageDescription(fileName: fileName, firstLine: firstLine) == .plainText)
  }
}
