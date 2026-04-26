//
//  ChatTests.swift
//  Slice 9 — verifies the SSE parser, the chat DTOs, and ChatService's
//  streaming state machine. Conversation history lives server-side
//  (keyed by conversation_id), so iOS doesn't need to track or send it.
//
//  Real backend SSE format from probe on 2026-04-26:
//    data: {"type":"text","content":"some chunk"}\n\n
//    data: {"type":"text","content":"more chunk"}\n\n
//    data: {"type":"done","message_id":"...","model":"haiku"}\n\n
//

import XCTest
@testable import FinanceTracker

@MainActor
final class ChatTests: XCTestCase {

    // MARK: - DTOs

    func testChatMessageCreateDTOEncodesContentAndModel() throws {
        let body = ChatMessageCreateDTO(content: "hi there", model: "haiku")
        let data = try JSONEncoder().encode(body)
        let asDict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(asDict["content"] as? String, "hi there")
        XCTAssertEqual(asDict["model"] as? String, "haiku")
    }

    func testConversationDTODecodesIdAndOptionalTitle() throws {
        let json = """
        {"id":"390ac4fa-eac9-4841-a5bd-4898dea3a0f1","title":null,
         "created_at":"2026-04-26T02:11:26.246067Z",
         "updated_at":"2026-04-26T02:11:26.246067Z"}
        """.data(using: .utf8)!
        let conv = try APIClient.makeDecoder().decode(ConversationDTO.self, from: json)
        XCTAssertEqual(conv.id.uuidString.lowercased(), "390ac4fa-eac9-4841-a5bd-4898dea3a0f1")
        XCTAssertNil(conv.title)
    }

    // MARK: - SSEParser

    func testSSEParserHandlesSingleCompleteEvent() {
        var parser = SSEParser()
        let events = parser.feed("data: {\"type\":\"text\",\"content\":\"hello\"}\n\n")
        XCTAssertEqual(events, ["{\"type\":\"text\",\"content\":\"hello\"}"])
    }

    func testSSEParserBuffersPartialChunks() {
        var parser = SSEParser()
        // First chunk: half of the line, no newline. Should yield nothing.
        let first = parser.feed("data: {\"type\":\"text\",\"con")
        XCTAssertEqual(first, [])
        // Second chunk: rest of line + the blank-line terminator. One event.
        let second = parser.feed("tent\":\"hi\"}\n\n")
        XCTAssertEqual(second, ["{\"type\":\"text\",\"content\":\"hi\"}"])
    }

    func testSSEParserHandlesMultipleEventsAndDoneSentinel() {
        var parser = SSEParser()
        let chunk = """
        data: {"type":"text","content":"one"}

        data: {"type":"text","content":"two"}

        data: {"type":"done","message_id":"abc"}


        """
        let events = parser.feed(chunk)
        XCTAssertEqual(events.count, 3)
        XCTAssertTrue(events[2].contains("\"done\""))
    }

    // MARK: - ChatService streaming

    func testChatServiceAppendsStreamingTokensToLastAssistantMessage() async {
        let service = ChatService(
            conversationFactory: { UUID() },
            streamer: { _, _ in
                AsyncThrowingStream { c in
                    c.yield("Hello ")
                    c.yield("world")
                    c.yield("!")
                    c.finish()
                }
            }
        )
        await service.send("hi")
        XCTAssertEqual(service.messages.count, 2)
        XCTAssertEqual(service.messages[0].role, .user)
        XCTAssertEqual(service.messages[0].content, "hi")
        XCTAssertEqual(service.messages[1].role, .assistant)
        XCTAssertEqual(service.messages[1].content, "Hello world!")
        XCTAssertEqual(service.state, .idle)
    }

    func testChatServiceFailureLeavesUserMessageWithErrorBubble() async {
        let service = ChatService(
            conversationFactory: { UUID() },
            streamer: { _, _ in
                AsyncThrowingStream { c in
                    c.yield("partial ")
                    c.finish(throwing: APIError.unknown("kaboom"))
                }
            }
        )
        await service.send("anything")
        XCTAssertEqual(service.messages.count, 2)
        XCTAssertEqual(service.messages[0].role, .user)
        XCTAssertEqual(service.messages[0].content, "anything", "user's original message must stay so they can retry")
        XCTAssertEqual(service.messages[1].role, .assistant)
        XCTAssertTrue(
            service.messages[1].content.contains("partial") ||
            service.messages[1].content.lowercased().contains("couldn't"),
            "assistant bubble should keep partial output OR show an error message"
        )
        if case .failed = service.state {} else {
            XCTFail("expected .failed state, got \(service.state)")
        }
    }
}
