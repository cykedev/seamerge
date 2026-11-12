extension LanguageSample {
  static let python = LanguageSample(
    language: "Python", fileName: "example.py",
    annotated: ###"""
      «c:#!/usr/bin/env python3»
      «s:"""Module docstring with 'quotes'»
      «s:spanning lines."""»

      «k:import» os

      «k:def» greet(name: str, count: int = «n:1») -> str:
          «c:# Comment with "quotes"»
          path = «s:r"C:\temp\new"»
          data = «s:b'\x00\xff'»
          message = «s:f"Hello, {»name.upper()«s:} {»count + «n:1»:>«n:4»«s:} {{braces}}"»
          «k:return» message «k:if» count > «n:0» «k:else» «k:None»

      value = «n:0x1F» + «n:1_000» + «n:3.5e-2» + «n:.5j»
      """###)
}
