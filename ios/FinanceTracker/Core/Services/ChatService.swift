//
//  ChatService.swift
//  Drives the Claude-powered finance assistant. The backend keeps
//  conversation state on its side, keyed by conversation_id — iOS just
//  POSTs new messages and streams the response. Endpoints (probed
//  2026-04-26):
//
//    POST /api/v1/chat/conversations
//      → ConversationDTO { id, title, created_at, updated_at }
//
//    POST /api/v1/chat/conversations/{id}/messages
//      Body: { content: String, model: String }
//      Returns text/event-stream with chunks like:
//        data: {"type":"text","content":"..."}\n\n
//        data: {"type":"done","message_id":"...","model":"haiku"}\n\n
//
//  iOS doesn't pass conversation_history because the server has it. We
//  also don't fetch the history on app launch — chat is session-scoped
//  for v1 (resets on sign-out).
//
//  Dependencies are injected as closures so unit tests can drive the
//  state machine with in-memory fakes; no fake APIClient required.
//

import Foundation
import Observation

@Observable @MainActor
final class ChatService {
    enum State: Equatable, Sendable { case idle, streaming, failed(String) }

    /// UI-facing message. Mutable `content` lets us append streaming
    /// tokens without rebuilding the array each time.
    struct Message: Identifiable, Equatable, Sendable {
        let id: UUID
        let role: ChatRole
        var content: String
        var isStreaming: Bool

        init(id: UUID = UUID(), role: ChatRole, content: String, isStreaming: Bool = false) {
            self.id = id
            self.role = role
            self.content = content
            self.isStreaming = isStreaming
        }
    }

    private(set) var state: State = .idle
    private(set) var messages: [Message] = []
    private(set) var conversationId: UUID?

    /// Pluggable suggestion list. Surfaced to the empty state.
    let suggestions: [String] = [
        "What did I spend this month?",
        "Where can I cut back?",
        "Should I pay off the credit card or the car loan first?"
    ]

    // Injected dependencies. Production wiring uses APIClient.
    private let conversationFactory: @Sendable () async throws -> UUID
    private let streamer: @Sendable (UUID, String) async throws -> AsyncThrowingStream<String, Error>

    init(
        conversationFactory: @escaping @Sendable () async throws -> UUID,
        streamer: @escaping @Sendable (UUID, String) async throws -> AsyncThrowingStream<String, Error>
    ) {
        self.conversationFactory = conversationFactory
        self.streamer = streamer
    }

    // MARK: - Public

    /// Send a user-typed message. Appends the user bubble immediately,
    /// then opens an empty assistant bubble that fills in token-by-token
    /// as the stream produces deltas.
    func send(_ rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard state != .streaming else { return }

        // Lazily create the conversation on first send. Failure here is
        // terminal for this attempt — surface it as an error bubble.
        let cid: UUID
        do {
            cid = try await currentConversationId()
        } catch {
            await failWith("Couldn't start a conversation. Try again.", userText: text)
            return
        }

        messages.append(Message(role: .user, content: text))
        let assistantIndex = messages.count
        messages.append(Message(role: .assistant, content: "", isStreaming: true))
        state = .streaming

        do {
            let stream = try await streamer(cid, text)
            for try await delta in stream {
                if assistantIndex < messages.count {
                    messages[assistantIndex].content += delta
                }
            }
            if assistantIndex < messages.count {
                messages[assistantIndex].isStreaming = false
            }
            state = .idle
        } catch {
            // Keep whatever partial content streamed before the failure;
            // mark the assistant bubble as not-streaming so the typing
            // indicator clears, and append a short failure note.
            if assistantIndex < messages.count {
                messages[assistantIndex].isStreaming = false
                let suffix = messages[assistantIndex].content.isEmpty
                    ? "Sorry — couldn't reach the chat service. Try again."
                    : "\n\n(stream interrupted — try again)"
                messages[assistantIndex].content += suffix
            }
            state = .failed(humanError(error))
        }
    }

    /// Wipe the local conversation. Server-side conversation row stays
    /// (for v1 — we'll add a delete endpoint call in 9b if Mom asks).
    func clear() {
        messages = []
        conversationId = nil
        state = .idle
    }

    /// AuthService.onSignOut hook — same shape as every other service.
    func reset() { clear() }

    // MARK: - Internals

    private func currentConversationId() async throws -> UUID {
        if let id = conversationId { return id }
        let id = try await conversationFactory()
        conversationId = id
        return id
    }

    private func failWith(_ msg: String, userText: String) async {
        messages.append(Message(role: .user, content: userText))
        messages.append(Message(role: .assistant, content: msg))
        state = .failed(msg)
    }

    private func humanError(_ err: Error) -> String {
        if let api = err as? APIError, let desc = api.errorDescription {
            return desc
        }
        return err.localizedDescription
    }
}

/// Decodes the `{"type":"text","content":"..."}` envelope the chat
/// endpoint emits. Returns nil for non-text events (the `done` sentinel
/// at end of stream, or any future event types we don't render).
enum ChatStreamEvent {
    private struct Envelope: Decodable {
        let type: String
        let content: String?
    }

    static func textDelta(from payload: String) -> String? {
        guard let data = payload.data(using: .utf8) else { return nil }
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        guard env.type == "text" else { return nil }
        return env.content
    }
}
