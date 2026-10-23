import Foundation
import XCTest
@testable import FrameTrailCore

final class SourceAnswerTests: XCTestCase {
    func testReferencesResolveToOriginalSnapshots() throws {
        let source = StoryFact(id: "wikipedia:12:34", text: "The original passage.", sourceURL: URL(string: "https://en.wikipedia.org/w/index.php?oldid=34"))
        let answer = SourceAnswer(paragraphs: [AnswerParagraph(text: "An explanation.", sourceIDs: ["R1", "R1"]), AnswerParagraph(text: "A different point.", sourceIDs: ["R1"])], evidence: [source])
        XCTAssertEqual(answer.citations.count, 1)
        XCTAssertEqual(answer.citations.first?.quote, source.text)
        XCTAssertTrue(answer.text.contains("An explanation. [1]"))
        XCTAssertFalse(answer.text.contains(source.id))
        let turn = ChatTurn(role: .assistant, text: answer.text, citations: answer.citations)
        let restored = try JSONDecoder().decode(ChatTurn.self, from: JSONEncoder().encode(turn))
        XCTAssertEqual(restored, turn)
    }

    func testUnknownAndUncitedParagraphsAreRejected() {
        let answer = SourceAnswer(paragraphs: [AnswerParagraph(text: "Invented", sourceIDs: ["R2"]), AnswerParagraph(text: "Unsupported", sourceIDs: [])], evidence: [StoryFact(id: "allowed", text: "Known")])
        XCTAssertTrue(answer.text.isEmpty)
        XCTAssertTrue(answer.citations.isEmpty)
    }

    func testOldMessagesRemainReadableWithoutExposingInternalIDs() throws {
        let data = Data("{\"id\":\"11111111-2222-3333-4444-555555555555\",\"role\":\"assistant\",\"text\":\"A point [wikipedia:12:34]. Другой [S1E2, S1E3].\",\"createdAt\":0}".utf8)
        let turn = try JSONDecoder().decode(ChatTurn.self, from: data)
        XCTAssertNil(turn.citations)
        let text = SourceAnswer.visibleText(turn.text)
        XCTAssertFalse(text.contains("wikipedia:"))
        XCTAssertFalse(text.contains("S1E2"))
        XCTAssertTrue(text.contains("Другой"))
    }
}
