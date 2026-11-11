import GitSupport
import Testing

struct ConflictMarkersTests {
  @Test func labelsOfAllThreeMarkersAreRead() {
    let text = """
      before
      <<<<<<< HEAD
      ours
      ||||||| 80d696f
      base
      =======
      theirs
      >>>>>>> feature
      after
      """

    let labels = ConflictMarkers.labels(in: text)

    #expect(labels == ConflictMarkerLabels(local: "HEAD", base: "80d696f", remote: "feature"))
  }

  @Test func conflictWithoutBaseMarkerHasNoBaseLabel() {
    let text = "<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> da986a1 (Change line 5)\n"

    let labels = ConflictMarkers.labels(in: text)

    #expect(
      labels == ConflictMarkerLabels(local: "HEAD", base: nil, remote: "da986a1 (Change line 5)"))
  }

  @Test func onlyTheFirstConflictCounts() {
    let text =
      "<<<<<<< one\na\n=======\nb\n>>>>>>> two\n<<<<<<< three\nc\n=======\nd\n>>>>>>> four\n"

    #expect(ConflictMarkers.labels(in: text)?.local == "one")
    #expect(ConflictMarkers.labels(in: text)?.remote == "two")
  }

  @Test func carriageReturnIsNotPartOfTheLabel() {
    let text = "<<<<<<< HEAD\r\nours\r\n=======\r\ntheirs\r\n>>>>>>> feature\r\n"

    #expect(
      ConflictMarkers.labels(in: text)
        == ConflictMarkerLabels(local: "HEAD", base: nil, remote: "feature"))
  }

  @Test func markerWithoutLabelHasNoLabel() {
    let text = "<<<<<<<\nours\n|||||||\nbase\n=======\ntheirs\n>>>>>>>"

    #expect(
      ConflictMarkers.labels(in: text) == ConflictMarkerLabels(local: nil, base: nil, remote: nil))
  }

  @Test func labelKeepsInnerSpacesAndLosesOuterOnes() {
    let text = "<<<<<<<  Updated upstream \nours\n=======\ntheirs\n>>>>>>> Stashed changes\n"

    #expect(ConflictMarkers.labels(in: text)?.local == "Updated upstream")
    #expect(ConflictMarkers.labels(in: text)?.remote == "Stashed changes")
  }

  @Test(arguments: [
    "<<<<<<<< long\na\n=======\nb\n>>>>>>> end\n",
    "<<<<<< short\na\n=======\nb\n>>>>>>> end\n",
    "<<<<<<<label\na\n=======\nb\n>>>>>>> end\n",
    "text <<<<<<< inside\na\n=======\nb\n>>>>>>> end\n",
  ])
  func linesThatOnlyResembleAStartMarkerAreText(text: String) {
    #expect(ConflictMarkers.labels(in: text) == nil)
  }

  @Test func conflictWithoutEndMarkerHasNoLabels() {
    #expect(ConflictMarkers.labels(in: "<<<<<<< HEAD\nours\n=======\ntheirs\n") == nil)
  }

  @Test func endMarkerBeforeSeparatorIsText() {
    let text = "<<<<<<< HEAD\n>>>>>>> early\n=======\ntheirs\n>>>>>>> feature\n"

    #expect(ConflictMarkers.labels(in: text)?.remote == "feature")
  }

  @Test func newStartMarkerBeginsTheConflictAgain() {
    let text = "<<<<<<< stray\ntext\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> feature\n"

    #expect(ConflictMarkers.labels(in: text)?.local == "HEAD")
  }

  @Test func textWithoutMarkersHasNoLabels() {
    #expect(ConflictMarkers.labels(in: "") == nil)
    #expect(ConflictMarkers.labels(in: "=======\n>>>>>>> feature\n") == nil)
  }
}
