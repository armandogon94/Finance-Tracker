//
//  APIError.swift
//  Normalised error surface for the networking layer. Every call
//  into APIClient returns one of these on failure so UI can render a
//  useful message without having to know URLError / DecodingError
//  specifics.
//

import Foundation

enum APIError: LocalizedError, Sendable {
    case network(URLError)
    case server(status: Int, detail: String?)
    case decoding(String)
    case unauthorized
    case notFound
    case rateLimited(retryAfterSeconds: Int?)
    case offline
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .network(let e):
            return "Network error: \(e.localizedDescription)"
        case .server(let status, let detail):
            if let detail, !detail.isEmpty { return detail }
            return "Server returned \(status)."
        case .decoding(let msg):
            return "Couldn't parse the server's response. (\(msg))"
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case .notFound:
            return "Not found."
        case .rateLimited(let retry):
            if let retry { return "Too many requests. Try again in \(retry)s." }
            return "Too many requests. Try again soon."
        case .offline:
            return "You appear to be offline."
        case .cancelled:
            return "Request was cancelled."
        case .unknown(let msg):
            return msg
        }
    }
}
