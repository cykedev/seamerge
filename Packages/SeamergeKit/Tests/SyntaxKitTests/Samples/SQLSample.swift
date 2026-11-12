extension LanguageSample {
  static let sql = LanguageSample(
    language: "SQL", fileName: "query.sql",
    annotated: ###"""
      «c:-- Find the active users»
      «k:SELECT» u.id, u.name «k:AS» «s:"User Name"»
      «k:FROM» users u
      «k:WHERE» u.active = «k:TRUE» «k:AND» u.note <> «s:'it''s -- not a comment'»
        «c:/* multi-line»
      «c:     comment */»
      «k:ORDER» «k:BY» u.id «k:DESC» «k:LIMIT» «n:10»;
      """###)
}
