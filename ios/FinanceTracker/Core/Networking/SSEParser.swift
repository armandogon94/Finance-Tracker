//
//  SSEParser.swift
//  Streaming parser for Server-Sent Events. Buffers across `feed(...)`
//  calls so a chunk that splits an event mid-line still parses cleanly.
//
//  We only care about `data:` lines — that's all the chat endpoint emits.
//  Comments (lines starting with `:`) and other event-stream metadata
//  (`event:`, `id:`, `retry:`) are ignored. The caller owns JSON-decoding
//  of the payload string we yield.
//
//  An "event" is terminated by a blank line (`\n\n`). Multiple `data:`
//  lines within one event are concatenated with `\n` per the spec, but
//  the chat endpoint always emits exactly one data line per event so we
//  never observe that case in practice.
//

import Foundation

struct SSEParser {
    private var buffer: String = ""

    /// Append a chunk and return any complete events the parser can now emit.
    /// Returns the raw payload after the `data: ` prefix has been stripped.
    mutating func feed(_ chunk: String) -> [String] {
        buffer += chunk
        var events: [String] = []

        // Parse off as many complete events as we can. An event ends with
        // a blank line. We support both `\n\n` and `\r\n\r\n` separators.
        while let range = buffer.rangeOfDoubleNewline() {
            let raw = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if let payload = parseEventBlock(raw) {
                events.append(payload)
            }
        }
        return events
    }

    /// Flush whatever's left in the buffer when the stream closes. Most
    /// servers terminate cleanly with a blank line, so this is usually a
    /// no-op — but worth calling so we don't drop a final orphan event.
    mutating func flush() -> [String] {
        guard !buffer.isEmpty else { return [] }
        let raw = buffer
        buffer = ""
        if let payload = parseEventBlock(raw) {
            return [payload]
        }
        return []
    }

    /// Returns the value after `data: ` (joined with `\n` if multi-line),
    /// or nil if the block has no `data:` line (e.g. comment-only).
    private func parseEventBlock(_ block: String) -> String? {
        var dataLines: [String] = []
        for raw in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : String(raw)
            if line.hasPrefix(":") { continue }     // comment
            if line.hasPrefix("data: ") {
                dataLines.append(String(line.dropFirst(6)))
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)))
            }
        }
        return dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
    }
}

private extension String {
    /// Earliest range matching `\n\n` or `\r\n\r\n`. Returns nil if neither
    /// is present (incomplete buffer).
    func rangeOfDoubleNewline() -> Range<String.Index>? {
        let lf = range(of: "\n\n")
        let crlf = range(of: "\r\n\r\n")
        switch (lf, crlf) {
        case (let a?, let b?): return a.lowerBound < b.lowerBound ? a : b
        case (let a?, nil):    return a
        case (nil, let b?):    return b
        case (nil, nil):       return nil
        }
    }
}
