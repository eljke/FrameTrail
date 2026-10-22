import Foundation
import XCTest
@testable import FrameTrailCore

final class SubtitleParserTests: XCTestCase {
    func testSRTImportsTextAndTimes() {
        let input = """
        1
        00:00:01,250 --> 00:00:03,500
        <i>Hello &amp; welcome.</i>
        A second line.

        2
        01:02:03,000 --> 01:02:04,000
        Later.
        """

        let cues = SubtitleParser.parse(input)

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].start, 1.25)
        XCTAssertEqual(cues[0].end, 3.5)
        XCTAssertEqual(cues[0].text, "Hello & welcome.\nA second line.")
        XCTAssertEqual(cues[1].start, 3723)
    }

    func testVTTImportsIdentifiersAndSkipsNotes() {
        let input = """
        WEBVTT

        NOTE This is not dialogue
        00:00.000 --> 00:01.000
        A hidden note.

        scene-1
        00:01.000 --> 00:02.400 align:start position:0%
        <v Ada>Hello.</v>

        STYLE
        ::cue { color: red; }

        00:03.000 --> 00:04.000
        Goodbye.
        """

        let cues = SubtitleParser.parse(input)

        XCTAssertEqual(cues.map(\.text), ["Hello.", "Goodbye."])
        XCTAssertEqual(cues[0].end, 2.4)
    }

    func testMalformedTimesDoNotBecomeValidCues() {
        let input = """
        1
        00:61:01,000 --> 01:02:00,000
        Invalid minute.

        2
        00:00:62,000 --> 00:02:00,000
        Invalid second.

        3
        -1:00:00,000 --> 00:01:00,000
        Negative time.

        4
        00:00:05,000 --> 00:00:04,000
        Reversed time.

        5
        00:00:02,xyz --> 00:00:04,000
        Invalid fraction.

        6
        00:00:03,000 --> 00:00:04,000
        Valid dialogue.
        """

        XCTAssertEqual(SubtitleParser.parse(input).map(\.text), ["Valid dialogue."])
    }

    func testBoundaryExcludesFutureAndSpanningCues() {
        let cues = [
            SubtitleCue(id: "future", start: 12, end: 14, text: "The ending."),
            SubtitleCue(id: "done", start: 1, end: 3, text: "The opening."),
            SubtitleCue(id: "spans", start: 4, end: 7, text: "The secret revealed mid-sentence.")
        ]

        let visible = SubtitleParser.cues(from: cues, through: 5)

        XCTAssertEqual(visible.map(\.id), ["done"])
        XCTAssertEqual(SubtitleParser.cues(from: cues, through: 7).map(\.id), ["done", "spans"])
    }

    func testTextBudgetIncludesSeparators() {
        let cues = [
            SubtitleCue(id: "a", start: 0, end: 1, text: "abc"),
            SubtitleCue(id: "b", start: 1, end: 2, text: "defgh"),
            SubtitleCue(id: "c", start: 2, end: 3, text: "xyz")
        ]

        XCTAssertEqual(SubtitleParser.text(from: cues, through: 10, maxCharacters: 6), "abc\nde")
        XCTAssertEqual(SubtitleParser.text(from: cues, through: 10, maxCharacters: 3), "abc")
        XCTAssertTrue(SubtitleParser.text(from: cues, through: 10, maxCharacters: 0).isEmpty)
    }

    func testInvalidBoundaryReturnsNothing() {
        let cues = [SubtitleCue(id: "a", start: 0, end: 1, text: "Dialogue.")]

        XCTAssertTrue(SubtitleParser.cues(from: cues, through: .infinity).isEmpty)
        XCTAssertTrue(SubtitleParser.cues(from: cues, through: -.infinity).isEmpty)
        XCTAssertTrue(SubtitleParser.cues(from: cues, through: .nan).isEmpty)
        XCTAssertTrue(SubtitleParser.cues(from: cues, through: -1).isEmpty)
    }

    func testCRLFAndBOMAreAccepted() {
        let input = "\u{FEFF}WEBVTT\r\n\r\n00:01.000 --> 00:02.000\r\nHello.\r\n"

        XCTAssertEqual(SubtitleParser.parse(input).map(\.text), ["Hello."])
    }
}
