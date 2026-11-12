import Testing

/// The constructs that a lexer most easily gets wrong, each on its own.
struct DifficultCaseTests {
  @Test func nestedBlockCommentsInSwiftEndAtTheMatchingDelimiter() {
    expectTokens(
      """
      «c:/* outer /* inner */ still outer»
      «c:/* deeper */ */» «k:let» x = «n:1»
      """, fileName: "a.swift")
  }

  @Test func blockCommentsInCDoNotNest() {
    expectTokens("«c:/* a /* b */» «k:int» x; «c:/* c */»", fileName: "a.c")
  }

  @Test func multiLineStringsInSwiftHoldCommentMarkersAndSingleQuotes() {
    expectTokens(
      #"""
      «k:let» poem = «s:"""»
      «s:  // not a comment, /* nor this, "nor" this»
      «s:  """»
      """#, fileName: "a.swift")
  }

  @Test func rawStringsInSwiftEndOnlyAtTheirOwnHashes() {
    expectTokens(
      ##"""
      «s:#"a "quoted" \(x) \"#» + «s:##"one "# two"##»
      «s:#"value: \#(»x«s:)"#»
      «s:#"""»
      «s:  """ is not the end»
      «s:  """#»
      """##, fileName: "a.swift")
  }

  @Test func interpolationsInSwiftHoldCodeAndStrings() {
    expectTokens(
      #"«s:"a \(»b ? «s:"c"» : «k:nil»«s:) d"» «k:let»"#, fileName: "a.swift")
  }

  @Test func rawStringsInRustIgnoreBackslashes() {
    expectTokens(
      ##"«s:r"C:\path\"» + «s:r#"a "b" c"#» + «s:"d\"e"»"##, fileName: "a.rs")
  }

  @Test func rawStringsInCPlusPlusEndAtTheirOwnDelimiter() {
    expectTokens(
      """
      «k:auto» s = «s:R"x(a )" b "c»
      «s:)x"»; «k:int» n;
      """, fileName: "a.cpp")
  }

  @Test(arguments: [
    ("a.py", ##"«s:"# not"» «c:# comment»"##),
    ("a.js", #"«s:'// not'» «c:// comment»"#),
    ("a.sql", #"«s:'it''s -- not'» «c:-- comment»"#),
    ("a.swift", #"«s:"/* not"» «c:/* comment */»"#),
    ("a.yaml", ##"key: «s:"# not"» «c:# comment»"##),
  ])
  func commentMarkersInsideStringsAreText(fileName: String, annotated: String) {
    expectTokens(annotated, fileName: fileName)
  }

  @Test func quotesInsideCommentsOpenNoString() {
    expectTokens(
      """
      «c:// "unclosed»
      «k:let» x = «n:1»
      """, fileName: "a.swift")
  }

  @Test func unclosedSingleLineStringEndsWithItsLine() {
    expectTokens(
      """
      «k:let» x = «s:"unclosed»
      «k:let» y = «n:2»
      """, fileName: "a.swift")
  }

  @Test func hereDocumentInShellRunsToItsTerminator() {
    expectTokens(
      #"""
      cat «s:<<EOF» | grep «s:"x"»
      «s:if "quoted" then # not code»
      «s:EOF»
      «k:if» true; «k:then» «k:fi»
      """#, fileName: "a.sh")
  }

  @Test func hereDocumentInShellTakesQuotedAndIndentedForms() {
    expectTokens(
      "cat «s:<< 'END'»\n«s:$HOME»\n«s:END»\ncat «s:<<-EOF»\n«s:\ttext»\n«s:\tEOF»\n«k:fi»",
      fileName: "a.sh")
  }

  @Test func hereStringInShellIsNoHereDocument() {
    expectTokens(
      """
      cat <<< word
      «k:fi»
      """, fileName: "a.sh")
  }

  @Test func commentInShellStartsOnlyAWord() {
    expectTokens(
      #"echo $# ${#a} a#b «c:# comment»"#, fileName: "a.sh")
  }

  @Test func lifetimesInRustAreNoCharacterLiterals() {
    expectTokens(
      #"«k:fn» f<'a>(x: &'a str) -> char { «k:return» «s:'x'» }"#, fileName: "a.rs")
  }

  @Test func apostropheInsideAPlainScalarIsText() {
    expectTokens(
      """
      title: Don't panic
      count: «n:1»
      """, fileName: "a.yaml")
  }

  @Test func blockScalarInYAMLEndsAtLesserIndentation() {
    expectTokens(
      """
      run: |
        «s:echo "a" # still the script»

        «s:done»
      next: «k:true»
      """, fileName: "a.yaml")
  }

  @Test func scriptContentInHTMLIsNoMarkup() {
    expectTokens(
      #"<«k:script»>if (a < b) { x = "</div>"; }</«k:script»> <«k:p»>"#, fileName: "a.html")
  }

  @Test func codeSpanInMarkdownClosesOnlyWithARunOfEqualLength() {
    expectTokens(
      "«s:``a ` b``» and «s:`c`» and ` alone", fileName: "a.md")
  }
}
