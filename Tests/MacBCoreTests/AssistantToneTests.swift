import XCTest
@testable import MacBCore

final class AssistantToneTests: XCTestCase {
    func testBuddyIsTheDefaultVoice() {
        XCTAssertEqual(JarvisPersona.defaultPersona, .buddy)
        XCTAssertEqual(JarvisPersona.allCases.first, .buddy)
        XCTAssertTrue(JarvisPersona.buddy.note.contains("kanka"))
    }

    func testJarvisBuddyInstructionsSoundHumanButKeepGuardrails() {
        let text = JarvisProtocol.instructions(now: Date(timeIntervalSince1970: 0),
                                               timeZone: TimeZone(secondsFromGMT: 0)!,
                                               persona: .buddy)
        XCTAssertTrue(text.contains("Mac buddy"))
        XCTAssertTrue(text.contains("kanka"))
        XCTAssertTrue(text.contains("Do not tease"))
        XCTAssertTrue(text.contains("You cannot delete files"))
    }

    func testWrittenAssistantUsesMacBTone() {
        let responses = AIResponseStream.requestBody(question: "Selam", model: "gpt-test")
        let responseInstructions = responses["instructions"] as? String ?? ""
        XCTAssertTrue(responseInstructions.contains("real kanka"))
        XCTAssertTrue(responseInstructions.contains("web search"))

        let chat = AIChatStream.requestBody(question: "Selam", model: "gpt-test")
        let messages = chat["messages"] as? [[String: Any]] ?? []
        let system = messages.first?["content"] as? String ?? ""
        XCTAssertTrue(system.contains("real kanka"))
        XCTAssertTrue(system.contains("cannot browse"))
    }
}
