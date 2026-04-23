//
//  ChatView.swift
//  AI Finance Chat — conversation list sidebar, chat bubbles, Haiku/Sonnet
//  model toggle. The streaming itself is faked with canned messages;
//  APIClient + SSE will replace this next phase.
//

import SwiftUI

struct ChatView: View {
    @Environment(\.appTheme) private var theme
    @State private var input = ""
    @State private var model: Model = .haiku
    @State private var conversations: [ChatConversation] = MockData.conversations
    @State private var selectedId: UUID? = MockData.conversations.first?.id
    @State private var messages: [ChatMessage] = MockData.messages
    @State private var showSidebar = false

    enum Model: String { case haiku, sonnet }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackdrop()

                VStack(spacing: 0) {
                    header
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(messages) { m in
                                ChatBubble(message: m)
                            }
                        }
                        .padding(16)
                    }
                    composer
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSidebar = true } label: { Image(systemName: "sidebar.left") }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSidebar) {
                ConversationSidebar(conversations: $conversations, selectedId: $selectedId)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(theme.id == .liquidGlass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(theme.background))
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(theme.accent)
                    Text("AI Finance Chat").font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
                }
                Text(conversations.first { $0.id == selectedId }?.title ?? "")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Picker("Model", selection: $model) {
                Text("Haiku").tag(Model.haiku)
                Text("Sonnet").tag(Model.sonnet)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(theme.id == .liquidGlass ? 0.7 : 0.0))
        .background(theme.surface)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "message").foregroundStyle(theme.textTertiary)
                TextField("Ask about your spending, debt, or budget…", text: $input)
                    .font(theme.font.body)
                    .foregroundStyle(theme.textPrimary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                    .fill(theme.surface)
            )

            Button {
                guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                messages.append(ChatMessage(id: UUID(), role: .user, content: input, timestamp: Date()))
                messages.append(ChatMessage(id: UUID(), role: .assistant,
                                            content: "Got it — I'd pull your last 30 days here and reply with Claude \(model.rawValue) streaming. (Skeleton UI.)",
                                            timestamp: Date()))
                input = ""
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(theme.accent))
            }
        }
        .padding(16)
        .background(theme.background.opacity(0.3))
    }
}

private struct ChatBubble: View {
    @Environment(\.appTheme) private var theme
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(message.content)
                    .font(theme.font.body)
                    .foregroundStyle(message.role == .user ? Color.black : theme.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(message.role == .user ? AnyShapeStyle(theme.accent)
                                                        : AnyShapeStyle(theme.cardBackground()))
                    )
            }
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

private struct ConversationSidebar: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Binding var conversations: [ChatConversation]
    @Binding var selectedId: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Button { conversations.insert(ChatConversation(id: UUID(), title: "New chat", lastMessagePreview: "", updatedAt: Date()), at: 0) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill").foregroundStyle(theme.accent)
                            Text("New conversation").font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                            Spacer()
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: theme.radii.card).fill(theme.surface))
                    }
                    ForEach(conversations) { c in
                        Button { selectedId = c.id; dismiss() } label: {
                            HStack(spacing: 12) {
                                Circle().fill(c.id == selectedId ? theme.accent : theme.textTertiary).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.title).font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                                    Text(c.lastMessagePreview).font(theme.font.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: theme.radii.card)
                                    .fill(c.id == selectedId ? theme.accent.opacity(0.18) : theme.surface)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview("Chat — Liquid Glass") {
    ChatView()
        .environment(\.appTheme, LiquidGlassTheme())
        .preferredColorScheme(.dark)
}
