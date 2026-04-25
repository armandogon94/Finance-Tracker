//
//  APIClient.swift
//  Single entry point for every call to the FastAPI backend.
//  Uses URLSession + async/await + Codable. Auth is handled by a
//  pluggable `TokenProvider` so the store stays decoupled from
//  Keychain specifics.
//

import Foundation

protocol TokenProvider: AnyObject, Sendable {
    func currentAccessToken() -> String?
    func updateAccessToken(_ token: String?) async
}

actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: (any TokenProvider)?
    private let decoder: JSONDecoder

    init(
        baseURL: URL = APIConfig.baseURL,
        tokenProvider: (any TokenProvider)? = nil,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        // Custom session with a delegate that re-attaches the Authorization
        // header when URLSession follows a redirect (FastAPI 307s bare paths
        // into their canonical trailing-slash form; the default delegate
        // strips auth on redirect for safety).
        let delegate = RedirectAuthDelegate(tokenProvider: tokenProvider)
        self.session = session ?? URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
        self.tokenProvider = tokenProvider
        self.decoder = APIClient.makeDecoder()
    }

    /// Shared decoder factory. Exposed as a static so unit tests can decode
    /// fixture JSON with the same date-format leniency as production
    /// (ISO8601 with or without fractional seconds, plus bare YYYY-MM-DD).
    static func makeDecoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .useDefaultKeys // backend uses snake_case; we map manually in models
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = iso.date(from: s) { return d }
            if let d = isoPlain.date(from: s) { return d }
            // date-only (YYYY-MM-DD) from the backend's `expense_date` etc.
            let dateOnly = DateFormatter()
            dateOnly.calendar = Calendar(identifier: .iso8601)
            dateOnly.locale = Locale(identifier: "en_US_POSIX")
            dateOnly.timeZone = TimeZone(identifier: "UTC")
            dateOnly.dateFormat = "yyyy-MM-dd"
            if let d = dateOnly.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Cannot parse date: \(s)")
        }
        return dec
    }

    // MARK: - Public API

    /// GET decoded to `T`.
    func get<T: Decodable & Sendable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let req = try await buildRequest(path: path, method: "GET", query: query, body: nil as EmptyBody?)
        return try await perform(req)
    }

    /// POST Encodable body decoded to `T`.
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B
    ) async throws -> T {
        let req = try await buildRequest(path: path, method: "POST", query: [:], body: body)
        return try await perform(req)
    }

    /// POST body returning no content (used for logout, etc.).
    func postVoid<B: Encodable & Sendable>(_ path: String, body: B) async throws {
        let req = try await buildRequest(path: path, method: "POST", query: [:], body: body)
        _ = try await performRaw(req)
    }

    /// PUT Encodable body decoded to `T`.
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B
    ) async throws -> T {
        let req = try await buildRequest(path: path, method: "PUT", query: [:], body: body)
        return try await perform(req)
    }

    /// PATCH Encodable body decoded to `T`.
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B
    ) async throws -> T {
        let req = try await buildRequest(path: path, method: "PATCH", query: [:], body: body)
        return try await perform(req)
    }

    /// DELETE no content.
    func delete(_ path: String) async throws {
        let req = try await buildRequest(path: path, method: "DELETE", query: [:], body: nil as EmptyBody?)
        _ = try await performRaw(req)
    }

    /// POST multipart/form-data with a single binary file part. Used by
    /// /api/v1/receipts/scan. The backend's parameter name is `file`.
    func uploadMultipart<T: Decodable & Sendable>(
        _ path: String,
        fileField: String = "file",
        fileName: String,
        mimeType: String,
        fileData: Data
    ) async throws -> T {
        let boundary = "FT-Boundary-\(UUID().uuidString)"
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.unknown("Bad URL: \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = tokenProvider?.currentAccessToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        return try await perform(req)
    }

    // MARK: - Request building

    private struct EmptyBody: Encodable, Sendable {}

    private func buildRequest<B: Encodable & Sendable>(
        path: String, method: String, query: [String: String], body: B?
    ) async throws -> URLRequest {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path, isDirectory: false),
                                        resolvingAgainstBaseURL: false) else {
            throw APIError.unknown("Bad URL: \(path)")
        }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else {
            throw APIError.unknown("Cannot assemble URL.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = tokenProvider?.currentAccessToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            req.httpBody = try enc.encode(body)
        }
        return req
    }

    // MARK: - Dispatch

    private func perform<T: Decodable & Sendable>(_ req: URLRequest) async throws -> T {
        let (data, resp) = try await performRaw(req)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            if let raw = String(data: data, encoding: .utf8) {
                print("[APIClient] decode failure for \(T.self): \(error)\nBody:\n\(raw)")
            }
            #endif
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func performRaw(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        #if DEBUG
        let started = Date()
        print("[APIClient] → \(req.httpMethod ?? "?") \(req.url?.absoluteString ?? "?")")
        #endif

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let urlErr as URLError {
            if urlErr.code == .cancelled { throw APIError.cancelled }
            if urlErr.code == .notConnectedToInternet ||
               urlErr.code == .networkConnectionLost {
                throw APIError.offline
            }
            throw APIError.network(urlErr)
        } catch {
            throw APIError.unknown(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown("Non-HTTP response")
        }

        #if DEBUG
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        print("[APIClient] ← \(http.statusCode) \(ms)ms \(req.url?.path ?? "")")
        #endif

        switch http.statusCode {
        case 200...299:
            return (data, http)
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
            throw APIError.rateLimited(retryAfterSeconds: retry)
        default:
            let detail = extractDetail(from: data)
            throw APIError.server(status: http.statusCode, detail: detail)
        }
    }

    // MARK: - Redirect handler

    /// Re-attaches the Authorization header when URLSession follows a
    /// redirect. Without this, FastAPI's 307 from bare `/foo` → `/foo/`
    /// strips the bearer token and the target endpoint 401s.
    final class RedirectAuthDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let tokenProvider: (any TokenProvider)?
        init(tokenProvider: (any TokenProvider)?) { self.tokenProvider = tokenProvider }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            // Only re-attach for same-host redirects.
            guard let originalHost = task.originalRequest?.url?.host,
                  let newHost = request.url?.host,
                  originalHost == newHost
            else {
                completionHandler(request)
                return
            }
            var forwarded = request
            if let token = tokenProvider?.currentAccessToken(),
               forwarded.value(forHTTPHeaderField: "Authorization") == nil {
                forwarded.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            completionHandler(forwarded)
        }
    }

    private func extractDetail(from data: Data) -> String? {
        // FastAPI errors come as { "detail": "…" } or { "detail": [...] }
        struct DetailWrapper: Decodable { let detail: StringOrArray? }
        enum StringOrArray: Decodable {
            case string(String)
            case array([FieldError])
            init(from decoder: Decoder) throws {
                if let s = try? decoder.singleValueContainer().decode(String.self) {
                    self = .string(s); return
                }
                let arr = try decoder.singleValueContainer().decode([FieldError].self)
                self = .array(arr)
            }
        }
        struct FieldError: Decodable { let msg: String? }

        guard let wrapper = try? JSONDecoder().decode(DetailWrapper.self, from: data),
              let detail = wrapper.detail else {
            return String(data: data, encoding: .utf8)
        }
        switch detail {
        case .string(let s): return s
        case .array(let errs): return errs.compactMap { $0.msg }.joined(separator: "; ")
        }
    }
}
