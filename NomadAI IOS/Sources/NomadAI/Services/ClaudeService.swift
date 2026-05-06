//
//  ClaudeService.swift
//  NomadAI — Claude API client (proxied through /api/claude)
//
//  See docs/api-contract.md and docs/business-logic.md.
//

import Foundation

actor ClaudeService {
    static let shared = ClaudeService()

    /// Production base URL — change to a preview alias for testing
    private let baseURL = URL(string: "https://nomadai.us")!

    enum ClaudeError: Error {
        case rateLimited(message: String)
        case http(status: Int, body: String)
        case malformedResponse
    }

    /// Decode-friendly response wrapper.
    struct Response: Codable {
        let content: [Block]
        struct Block: Codable {
            let type: String
            let text: String?
        }

        var text: String {
            content.compactMap { $0.text }.joined()
        }
    }

    /// Send a Messages-API request through `/api/claude`.
    /// - Parameters:
    ///   - model: e.g. "claude-haiku-4-5-20251001" or "claude-sonnet-4-5-20241022"
    ///   - maxTokens: 4000 default, 8000 for route queries
    ///   - userPrompt: the full user content string (system + history + new query)
    func send(model: String, maxTokens: Int, userPrompt: String) async throws -> Response {
        var req = URLRequest(url: baseURL.appending(path: "/api/claude"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.malformedResponse
        }

        if http.statusCode == 429 {
            // Rate limit envelope: { "error": { "type": "rate_limit", "message": "..." } }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let msg = err["message"] as? String {
                throw ClaudeError.rateLimited(message: msg)
            }
            throw ClaudeError.rateLimited(message: "Rate limit reached.")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.http(status: http.statusCode, body: body)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }
}

// MARK: - Query classification (port of app.html:3348-3349)

enum QueryKind { case appQuestion, route, location }

func classifyQuery(_ query: String) -> QueryKind {
    let q = query.lowercased()

    let appQuestion = #"(^|\s)(what can|how do|how does|how to|what is|what are|what do|who are|tell me|explain|help me|features|capabilities|can you|do you|are you|how work|nomadai|about you|about this|where is|what.s in|good time|best time|weather in|things to do|near.*what|recommend|suggest|tips for|far from|drive.*from|distance)"#
    if q.range(of: appQuestion, options: .regularExpression) != nil {
        return .appQuestion
    }

    let route = #"along|on the way|on my way|en route|between .* and|from .* to|drive.*through|road trip|highway|interstate|\bI-\d|\bUS-\d|\bhwy\b|\broute\b.*\d"#
    if q.range(of: route, options: .regularExpression) != nil {
        return .route
    }

    return .location
}

// MARK: - Model selection per query kind

extension ClaudeService {
    static func model(for kind: QueryKind) -> String {
        switch kind {
        case .route: return "claude-sonnet-4-5-20241022"
        default: return "claude-haiku-4-5-20251001"
        }
    }

    static func maxTokens(for kind: QueryKind) -> Int {
        switch kind {
        case .route: return 8000
        case .appQuestion: return 3000
        case .location: return 4000
        }
    }
}
