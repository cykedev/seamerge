extension LanguageSample {
  static let yaml = LanguageSample(
    language: "YAML", fileName: "config.yml",
    annotated: ###"""
      «c:# Settings»
      name: Demo app
      title: Don't panic
      enabled: «k:true»
      count: «n:42»
      ratio: «n:-0.5»
      version: «n:1.2.3»
      empty: «k:~»
      quoted: «s:"a # not a comment"»
      single: «s:'it''s'»
      url: http://example.com/#anchor «c:# comment»
      items:
        - one
        - «n:2»
        - «s:"three"»
      script: |
        «s:echo "hello"»
        «s:# still the script»

        «s:done»
      after: «k:yes»
      nested:
        - key: >-
            «s:folded text»
          other: «k:false»
      """###)
}
