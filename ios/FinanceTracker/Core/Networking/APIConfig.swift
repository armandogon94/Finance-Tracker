//
//  APIConfig.swift
//  Backend base URL resolution. Reads -apiBase launch arg first,
//  then FT_API_BASE env var, then falls back to the localhost dev URL.
//  On Simulator `localhost` maps to the host Mac, so the FastAPI dev
//  server on port 8040 is reachable as-is. For a real device, pass
//  -apiBase=http://<mac-lan-ip>:8040 at launch.
//

import Foundation

enum APIConfig {
    static var baseURL: URL {
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-apiBase=") }) {
            let raw = String(arg.dropFirst("-apiBase=".count))
            if let url = URL(string: raw) { return url }
        }
        if let env = ProcessInfo.processInfo.environment["FT_API_BASE"], let url = URL(string: env) {
            return url
        }
        return URL(string: "http://localhost:8040")!
    }
}
