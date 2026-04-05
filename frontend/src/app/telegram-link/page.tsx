"use client";

import React, { useState } from "react";
import { Send, Copy, Check, RefreshCw, Loader2, ExternalLink } from "lucide-react";
import { useAuth } from "@/contexts/AuthContext";
import { api } from "@/lib/api";
import Navigation from "@/components/Navigation";

export default function TelegramLinkPage() {
  const { user, isLoading: authLoading } = useAuth();
  const [code, setCode] = useState<string | null>(null);
  const [expiresAt, setExpiresAt] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const generateCode = async () => {
    setLoading(true);
    setError(null);
    try {
      const result = await api.generateTelegramLink();
      setCode(result.code);
      setExpiresAt(result.expires_at);
    } catch (err) {
      setError("Failed to generate link code. Please try again.");
    } finally {
      setLoading(false);
    }
  };

  const copyCode = async () => {
    if (!code) return;
    await navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

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
        <p className="text-gray-500">Please log in first.</p>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50 pb-20">
      <div className="max-w-md mx-auto px-4 pt-6">
        {/* Header */}
        <div className="flex items-center gap-3 mb-6">
          <div className="h-10 w-10 bg-blue-100 rounded-xl flex items-center justify-center">
            <Send className="h-5 w-5 text-blue-600" />
          </div>
          <div>
            <h1 className="text-lg font-semibold text-gray-800">Link Telegram</h1>
            <p className="text-xs text-gray-500">Log expenses from Telegram</p>
          </div>
        </div>

        {/* Instructions */}
        <div className="bg-white rounded-2xl border border-gray-200 p-5 mb-4">
          <h2 className="text-sm font-semibold text-gray-800 mb-3">How it works</h2>
          <ol className="space-y-3 text-sm text-gray-600">
            <li className="flex gap-3">
              <span className="flex-shrink-0 w-6 h-6 bg-primary-100 text-primary-600 rounded-full
                             flex items-center justify-center text-xs font-bold">1</span>
              <span>Generate a link code below</span>
            </li>
            <li className="flex gap-3">
              <span className="flex-shrink-0 w-6 h-6 bg-primary-100 text-primary-600 rounded-full
                             flex items-center justify-center text-xs font-bold">2</span>
              <span>
                Open <strong>@ArmandoFinanceBot</strong> on Telegram
              </span>
            </li>
            <li className="flex gap-3">
              <span className="flex-shrink-0 w-6 h-6 bg-primary-100 text-primary-600 rounded-full
                             flex items-center justify-center text-xs font-bold">3</span>
              <span>
                Send: <code className="bg-gray-100 px-1.5 py-0.5 rounded text-xs">/verify YOUR_CODE</code>
              </span>
            </li>
          </ol>
        </div>

        {/* Generate / Show code */}
        <div className="bg-white rounded-2xl border border-gray-200 p-5">
          {!code ? (
            <button
              onClick={generateCode}
              disabled={loading}
              className="w-full flex items-center justify-center gap-2 px-4 py-3 bg-primary-500
                         text-white rounded-xl hover:bg-primary-600 disabled:opacity-50
                         transition-colors font-medium text-sm"
            >
              {loading ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <RefreshCw className="h-4 w-4" />
              )}
              Generate Link Code
            </button>
          ) : (
            <div className="text-center">
              <p className="text-xs text-gray-500 mb-2">Your link code</p>
              <div className="flex items-center justify-center gap-3 mb-3">
                <code className="text-2xl font-mono font-bold text-primary-600 tracking-widest">
                  {code}
                </code>
                <button
                  onClick={copyCode}
                  className="p-2 text-gray-400 hover:text-gray-600 transition-colors"
                >
                  {copied ? (
                    <Check className="h-5 w-5 text-green-500" />
                  ) : (
                    <Copy className="h-5 w-5" />
                  )}
                </button>
              </div>
              {expiresAt && (
                <p className="text-xs text-gray-400">
                  Expires in 24 hours
                </p>
              )}

              <div className="mt-4 pt-4 border-t border-gray-100">
                <p className="text-xs text-gray-500 mb-2">
                  Send this to the bot on Telegram:
                </p>
                <code className="text-sm bg-gray-100 px-3 py-1.5 rounded-lg text-gray-700">
                  /verify {code}
                </code>
              </div>

              <button
                onClick={generateCode}
                className="mt-4 text-xs text-gray-400 hover:text-gray-600 transition-colors"
              >
                Generate new code
              </button>
            </div>
          )}

          {error && (
            <p className="mt-3 text-xs text-red-500 text-center">{error}</p>
          )}
        </div>
      </div>

      <Navigation />
    </div>
  );
}
