"use client";

import React, { useState, useEffect, useRef, useCallback } from "react";
import {
  MessageCircle,
  Send,
  Plus,
  Trash2,
  Settings,
  ChevronLeft,
  Sparkles,
  Loader2,
} from "lucide-react";
import { useAuth } from "@/contexts/AuthContext";
import { api } from "@/lib/api";
import Navigation from "@/components/Navigation";
import type { ChatConversation, ChatMessage } from "@/types";

// ─── Suggested prompts for empty chat ──────────────────────────────

const SUGGESTED_PROMPTS = [
  { icon: "📊", label: "Monthly spending summary" },
  { icon: "💳", label: "Debt payoff timeline" },
  { icon: "🏷️", label: "Top expense categories" },
  { icon: "📈", label: "Spending trends analysis" },
  { icon: "💰", label: "Budget status check" },
  { icon: "🎯", label: "Where can I save money?" },
];

// ─── Component ─────────────────────────────────────────────────────

export default function ChatPage() {
  const { user, isLoading: authLoading } = useAuth();

  // State
  const [conversations, setConversations] = useState<ChatConversation[]>([]);
  const [activeConversationId, setActiveConversationId] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [isStreaming, setIsStreaming] = useState(false);
  const [streamingContent, setStreamingContent] = useState("");
  const [model, setModel] = useState<"haiku" | "sonnet">("haiku");
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [showSettings, setShowSettings] = useState(false);

  const messagesEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  // ── Load conversations ───────────────────────────────────────────

  const loadConversations = useCallback(async () => {
    try {
      const data = await api.getConversations();
      setConversations(data || []);
    } catch {
      // Silently handle — user may not have any conversations yet
    }
  }, []);

  useEffect(() => {
    if (user) loadConversations();
  }, [user, loadConversations]);

  // ── Load messages for active conversation ────────────────────────

  useEffect(() => {
    if (!activeConversationId) {
      setMessages([]);
      return;
    }

    const loadMessages = async () => {
      try {
        const data = await api.getMessages(activeConversationId);
        setMessages(data?.items || []);
      } catch {
        setMessages([]);
      }
    };
    loadMessages();
  }, [activeConversationId]);

  // ── Auto-scroll to bottom ────────────────────────────────────────

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, streamingContent]);

  // ── Create new conversation ──────────────────────────────────────

  const createNewConversation = async () => {
    try {
      const conv = await api.createConversation();
      setConversations((prev) => [conv, ...prev]);
      setActiveConversationId(conv.id);
      setMessages([]);
      setSidebarOpen(false);
    } catch (err) {
      console.error("Failed to create conversation:", err);
    }
  };

  // ── Delete conversation ──────────────────────────────────────────

  const deleteConversation = async (id: string) => {
    try {
      await api.deleteConversation(id);
      setConversations((prev) => prev.filter((c) => c.id !== id));
      if (activeConversationId === id) {
        setActiveConversationId(null);
        setMessages([]);
      }
    } catch (err) {
      console.error("Failed to delete conversation:", err);
    }
  };

  // ── Send message ─────────────────────────────────────────────────

  const sendMessage = async (content?: string) => {
    const messageText = content || input.trim();
    if (!messageText || isStreaming) return;

    let conversationId = activeConversationId;

    // Create conversation if none active
    if (!conversationId) {
      try {
        const conv = await api.createConversation();
        setConversations((prev) => [conv, ...prev]);
        conversationId = conv.id;
        setActiveConversationId(conv.id);
      } catch {
        return;
      }
    }

    // At this point conversationId is guaranteed non-null
    const activeId = conversationId!;

    // Optimistic UI: add user message immediately
    const userMsg: ChatMessage = {
      id: `temp-${Date.now()}`,
      conversation_id: activeId,
      role: "user",
      content: messageText,
      model_used: null,
      tokens_used: null,
      created_at: new Date().toISOString(),
    };
    setMessages((prev) => [...prev, userMsg]);
    setInput("");
    setIsStreaming(true);
    setStreamingContent("");

    try {
      const response = await api.sendChatMessage(activeId, messageText, model);
      const reader = response.body?.getReader();
      const decoder = new TextDecoder();

      if (!reader) throw new Error("No response body");

      let fullContent = "";
      let buffer = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() || "";

        for (const line of lines) {
          if (!line.startsWith("data: ")) continue;
          try {
            const data = JSON.parse(line.slice(6));
            if (data.type === "text") {
              fullContent += data.content;
              setStreamingContent(fullContent);
            } else if (data.type === "done") {
              // Add completed assistant message
              const assistantMsg: ChatMessage = {
                id: data.message_id || `assistant-${Date.now()}`,
                conversation_id: activeId,
                role: "assistant",
                content: fullContent,
                model_used: data.model,
                tokens_used: null,
                created_at: new Date().toISOString(),
              };
              setMessages((prev) => [...prev, assistantMsg]);
              setStreamingContent("");
            }
          } catch {
            // Skip malformed SSE lines
          }
        }
      }
    } catch (err) {
      console.error("Chat error:", err);
      const errorMsg: ChatMessage = {
        id: `error-${Date.now()}`,
        conversation_id: activeId,
        role: "assistant",
        content: "Sorry, I encountered an error. Please try again.",
        model_used: null,
        tokens_used: null,
        created_at: new Date().toISOString(),
      };
      setMessages((prev) => [...prev, errorMsg]);
      setStreamingContent("");
    } finally {
      setIsStreaming(false);
      loadConversations(); // Refresh sidebar titles
    }
  };

  // ── Handle keyboard ──────────────────────────────────────────────

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  };

  // ── Auth guard ───────────────────────────────────────────────────

  if (authLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <Loader2 className="h-8 w-8 animate-spin text-primary-500" />
      </div>
    );
  }

  if (!user) {
    return (
      <div className="flex items-center justify-center min-h-screen p-4">
        <p className="text-gray-500">Please log in to use AI Chat.</p>
      </div>
    );
  }

  // ── Render ───────────────────────────────────────────────────────

  const hasMessages = messages.length > 0 || streamingContent;

  return (
    <div className="flex h-screen bg-gray-50">
      {/* Sidebar */}
      <div
        className={`fixed inset-y-0 left-0 z-50 w-72 bg-white border-r border-gray-200
                    transform transition-transform duration-200 ease-out
                    ${sidebarOpen ? "translate-x-0" : "-translate-x-full"}
                    md:relative md:translate-x-0 md:block`}
      >
        <div className="flex flex-col h-full">
          <div className="p-4 border-b border-gray-100">
            <button
              onClick={createNewConversation}
              className="w-full flex items-center gap-2 px-4 py-2.5 bg-primary-500 text-white
                         rounded-xl hover:bg-primary-600 transition-colors text-sm font-medium"
            >
              <Plus className="h-4 w-4" />
              New Chat
            </button>
          </div>

          <div className="flex-1 overflow-y-auto p-2">
            {conversations.map((conv) => (
              <div
                key={conv.id}
                className={`group flex items-center gap-2 px-3 py-2.5 rounded-lg cursor-pointer
                           text-sm transition-colors mb-0.5
                           ${
                             activeConversationId === conv.id
                               ? "bg-primary-50 text-primary-700"
                               : "text-gray-700 hover:bg-gray-100"
                           }`}
                onClick={() => {
                  setActiveConversationId(conv.id);
                  setSidebarOpen(false);
                }}
              >
                <MessageCircle className="h-4 w-4 flex-shrink-0" />
                <span className="flex-1 truncate">
                  {conv.title || "New Chat"}
                </span>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    deleteConversation(conv.id);
                  }}
                  className="hidden group-hover:block text-gray-400 hover:text-red-500"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Sidebar overlay on mobile */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 z-40 bg-black/20 md:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* Main chat area */}
      <div className="flex-1 flex flex-col min-w-0">
        {/* Chat header */}
        <div className="flex items-center gap-3 px-4 py-3 border-b border-gray-100 bg-white">
          <button
            onClick={() => setSidebarOpen(true)}
            className="md:hidden text-gray-500"
          >
            <ChevronLeft className="h-5 w-5" />
          </button>

          <Sparkles className="h-5 w-5 text-primary-500" />
          <h1 className="text-base font-semibold text-gray-800 flex-1">
            AI Finance Chat
          </h1>

          {/* Model toggle */}
          <div className="flex items-center gap-1 bg-gray-100 rounded-lg p-0.5 text-xs">
            <button
              onClick={() => setModel("haiku")}
              className={`px-2.5 py-1 rounded-md transition-colors ${
                model === "haiku"
                  ? "bg-white text-primary-600 shadow-sm font-medium"
                  : "text-gray-500 hover:text-gray-700"
              }`}
            >
              Haiku
            </button>
            <button
              onClick={() => setModel("sonnet")}
              className={`px-2.5 py-1 rounded-md transition-colors ${
                model === "sonnet"
                  ? "bg-white text-primary-600 shadow-sm font-medium"
                  : "text-gray-500 hover:text-gray-700"
              }`}
            >
              Sonnet
            </button>
          </div>
        </div>

        {/* Messages area */}
        <div className="flex-1 overflow-y-auto px-4 py-6 pb-32">
          {!hasMessages ? (
            /* Empty state with suggested prompts */
            <div className="flex flex-col items-center justify-center h-full max-w-md mx-auto">
              <Sparkles className="h-12 w-12 text-primary-300 mb-4" />
              <h2 className="text-lg font-semibold text-gray-800 mb-2">
                AI Finance Assistant
              </h2>
              <p className="text-sm text-gray-500 text-center mb-8">
                Ask me about your spending, budgets, or debt strategies.
                I have access to your financial data.
              </p>

              <div className="grid grid-cols-2 gap-2 w-full">
                {SUGGESTED_PROMPTS.map((prompt) => (
                  <button
                    key={prompt.label}
                    onClick={() => sendMessage(prompt.label)}
                    className="flex items-center gap-2 px-3 py-2.5 bg-white border border-gray-200
                               rounded-xl text-sm text-gray-700 hover:bg-gray-50 hover:border-gray-300
                               transition-colors text-left"
                  >
                    <span>{prompt.icon}</span>
                    <span className="line-clamp-2">{prompt.label}</span>
                  </button>
                ))}
              </div>
            </div>
          ) : (
            /* Message list */
            <div className="max-w-2xl mx-auto space-y-4">
              {messages.map((msg) => (
                <div
                  key={msg.id}
                  className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}
                >
                  <div
                    className={`max-w-[85%] px-4 py-2.5 rounded-2xl text-sm leading-relaxed
                               ${
                                 msg.role === "user"
                                   ? "bg-primary-500 text-white rounded-br-md"
                                   : "bg-white border border-gray-200 text-gray-800 rounded-bl-md"
                               }`}
                  >
                    <div className="whitespace-pre-wrap">{msg.content}</div>
                    {msg.role === "assistant" && msg.model_used && (
                      <div className="mt-1.5 text-[10px] text-gray-400">
                        {msg.model_used}
                      </div>
                    )}
                  </div>
                </div>
              ))}

              {/* Streaming message */}
              {streamingContent && (
                <div className="flex justify-start">
                  <div className="max-w-[85%] px-4 py-2.5 rounded-2xl rounded-bl-md
                                 bg-white border border-gray-200 text-sm text-gray-800 leading-relaxed">
                    <div className="whitespace-pre-wrap">{streamingContent}</div>
                    <span className="inline-block w-1.5 h-4 bg-primary-400 animate-pulse ml-0.5" />
                  </div>
                </div>
              )}

              {/* Loading indicator */}
              {isStreaming && !streamingContent && (
                <div className="flex justify-start">
                  <div className="px-4 py-3 bg-white border border-gray-200 rounded-2xl rounded-bl-md">
                    <div className="flex gap-1">
                      <span className="w-2 h-2 bg-gray-300 rounded-full animate-bounce" style={{ animationDelay: "0ms" }} />
                      <span className="w-2 h-2 bg-gray-300 rounded-full animate-bounce" style={{ animationDelay: "150ms" }} />
                      <span className="w-2 h-2 bg-gray-300 rounded-full animate-bounce" style={{ animationDelay: "300ms" }} />
                    </div>
                  </div>
                </div>
              )}

              <div ref={messagesEndRef} />
            </div>
          )}
        </div>

        {/* Input area */}
        <div className="fixed bottom-16 left-0 right-0 md:left-72 bg-gradient-to-t from-gray-50
                        via-gray-50 to-transparent pt-6 px-4 pb-4">
          <div className="max-w-2xl mx-auto">
            <div className="flex items-end gap-2 bg-white border border-gray-200 rounded-2xl
                           shadow-sm px-4 py-2">
              <textarea
                ref={inputRef}
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="Ask about your finances..."
                rows={1}
                className="flex-1 resize-none bg-transparent text-sm text-gray-800
                          placeholder:text-gray-400 focus:outline-none max-h-32 py-1.5"
                style={{ minHeight: "36px" }}
              />
              <button
                onClick={() => sendMessage()}
                disabled={!input.trim() || isStreaming}
                className="flex-shrink-0 p-2 rounded-xl bg-primary-500 text-white
                          hover:bg-primary-600 disabled:opacity-40 disabled:cursor-not-allowed
                          transition-colors"
              >
                {isStreaming ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Send className="h-4 w-4" />
                )}
              </button>
            </div>
          </div>
        </div>
      </div>

      <Navigation />
    </div>
  );
}
