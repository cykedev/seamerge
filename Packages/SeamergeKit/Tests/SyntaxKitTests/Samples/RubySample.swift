extension LanguageSample {
  static let ruby = LanguageSample(
    language: "Ruby", fileName: "example.rb",
    annotated: ###"""
      «c:# frozen_string_literal: true»
      «c:=begin»
      «c:A block comment»
      «c:=end»
      «k:class» Greeter
        attr_reader :name

        «k:def» greet(count = «n:1»)
          message = «s:"Hello, #{»name.upcase«s:} #{»count + «n:1»«s:}"»
          text = «s:<<~TEXT»
      «s:      Here document with "quotes" and #{name}»
      «s:    TEXT»
          single = «s:'it\'s'»
          «k:return» message «k:unless» count.zero?
        «k:end»
      «k:end»
      """###)
}
