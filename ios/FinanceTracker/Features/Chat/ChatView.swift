//
//  ChatView.swift
//  Slice 9 — Claude-powered finance assistant. Conversation lives on
//  the server (keyed by ChatService.conversationId) so iOS just renders
//  the bubble list, autoscrolls on new content, and POSTs new messages
//  to the SSE endpoint via ChatService.
//

import SwiftUI

struct ChatView: View {
    @Environment(\.appTheme) private var theme
    @Environment(ChatService.self) private var chat

    @State private var draft: String = ""
    @State private var showClearConfirm = false
    @State private var sendStamp = 0
    @State private var errorStamp = 0
    @FocusState private var inputFocused: Bool

    private var canSend: Bool {
        chat.state != .streaming
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackdrop()
                VStack(spacing: 0) {
                    if chat.messages.isEmpty {
                        emptyState
                    } else {
                        messagesScroll
                    }
                    inputBar
                }
            }
            .navigationTitle("Finance assistant")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if !chat.messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Image(systemName: "trash").foregroundStyle(theme.negative)
                        }
                    }
                }
            }
        }
        .alert("Clear conversation?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { chat.clear() }
        } message: {
            Text("This deletes the chat from your phone. Your expenses and budgets aren't affected.")
        }
        .sensoryFeedback(.selection, trigger: sendStamp)
        .sensoryFeedback(.error, trigger: errorStamp)
        .onChange(of: chat.state) { _, new in
            if case .failed = new { errorStamp += 1 }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 24)
            Image(systemName: "sparkles")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(theme.accent)
            VStack(spacing: 6) {
                Text("Ask about your money")
                    .font(theme.font.title)
                    .foregroundStyle(theme.textPrimary)
                Text("Claude can see your expenses, categories, and debt — ask anything.")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            VStack(spacing: 10) {
                ForEach(chat.suggestions, id: \.self) { suggestion in
                    Button {
                        draft = suggestion
                        inputFocused = true
                    } label: {
                        HStack {
                            Text(suggestion)
                                .font(theme.font.bodyMedium)
                                .foregroundStyle(theme.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.left").foregroundStyle(theme.textTertiary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            Spacer()
        }
    }

    // MARK: - Messages

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(chat.messages) { msg in
                        bubble(msg)
                            .id(msg.id)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .onAppear { scrollToBottom(proxy: proxy, animated: false) }
            .onChange(of: chat.messages.count) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: chat.messages.last?.content) { _, _ in
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
    }

    private static let bottomAnchor = "ft.chat.bottom"

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    @ViewBuilder
    private func bubble(_ msg: ChatService.Message) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(msg.content)
                    .font(theme.font.body)
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        case .assistant:
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if !msg.content.isEmpty {
                        Text(msg.content)
                            .font(theme.font.body)
                            .foregroundStyle(theme.textPrimary)
                            .textSelection(.enabled)
                    }
                    if msg.isStreaming {
                        TypingIndicator(color: theme.textTertiary)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Spacer(minLength: 40)
            }
        case .system:
            EmptyView()
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask a question…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .font(theme.font.body)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .submitLabel(.send)
                .onSubmit { tapSend() }

            Button {
                tapSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(canSend ? theme.accent : theme.accent.opacity(0.4))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.background.opacity(0.95))
    }

    private func tapSend() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        sendStamp += 1
        Task { await chat.send(text) }
    }
}

// MARK: - Typing indicator

private struct TypingIndicator: View {
    let color: Color
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1.0 : 0.35)
            }
        }
        .padding(.vertical, 2)
        .task {
            // 0 → 1 → 2 → 0 every 0.4s. Task gets cancelled when this
            // bubble's `isStreaming` flips false and the view rebuilds.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                phase = (phase + 1) % 3
            }
        }
    }
}

#Preview("Chat — Liquid Glass") {
    ChatView()
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(ChatService(
            conversationFactory: { UUID() },
            streamer: { _, _ in
                AsyncThrowingStream { c in c.finish() }
            }
        ))
        .preferredColorScheme(.dark)
}
