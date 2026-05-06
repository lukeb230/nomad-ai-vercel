//
//  ClaudeService.swift
//  NomadAI — Claude API client (proxied through the Supabase Edge Function `claude`).
//
//  See docs/api-contract.md and docs/business-logic.md.
//

import Foundation
import Supabase

actor ClaudeService {
    static let shared = ClaudeService()

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

    /// Send a Messages-API request through the `claude` Supabase Edge Function.
    /// The function injects the `cache_control: ephemeral` block for prompt caching.
    /// - Parameters:
    ///   - model: e.g. "claude-haiku-4-5-20251001" or "claude-sonnet-4-6"
    ///   - maxTokens: 4000 default, 8000 for route queries
    ///   - system: optional Anthropic top-level `system` framing (NomadAIPersona.systemPrompt)
    ///   - history: prior conversation turns, in order (excluding the latest user
    ///     turn — that's `userPrompt`). For AI turns we send each message's
    ///     `claudeText` (full response with JSON) when available, falling back
    ///     to `text` (display version). Empty array = single-turn call.
    ///   - userPrompt: the latest user turn — typically the user's typed query
    ///     plus per-kind format/grounding instructions appended.
    ///   - maxWebSearches: cap on Anthropic's web_search tool calls. 0 = tool
    ///     not attached (saves ~50 tokens of tool definition + Claude can't
    ///     trigger searches). >0 = tool attached with that ceiling. Each call
    ///     costs ~$0.01. Default 0; callers should pass 1 for normal grounding
    ///     (Claude rarely fires it) and 3 for closure / current-condition queries.
    func send(
        model: String,
        maxTokens: Int,
        system: String? = nil,
        history: [ChatMessage] = [],
        userPrompt: String,
        maxWebSearches: Int = 0
    ) async throws -> Response {
        // Build the messages array: prior turns + the new user turn.
        // We cap history at the most recent 12 turns to keep context bounded;
        // Anthropic supports 200K but cost grows linearly per turn.
        let trimmedHistory = history.suffix(12)
        var messages: [AnyJSON] = []
        for msg in trimmedHistory {
            let role = msg.role == .user ? "user" : "assistant"
            let content = msg.claudeText ?? msg.text
            // Skip empty content — Anthropic rejects empty messages.
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            messages.append(.object([
                "role": .string(role),
                "content": .string(content),
            ]))
        }
        messages.append(.object([
            "role": .string("user"),
            "content": .string(userPrompt),
        ]))

        var payload: [String: AnyJSON] = [
            "model": .string(model),
            "max_tokens": .integer(maxTokens),
            "messages": .array(messages),
        ]
        if let system { payload["system"] = .string(system) }
        if maxWebSearches > 0 {
            payload["tools"] = .array([
                .object([
                    "type": .string("web_search_20250305"),
                    "name": .string("web_search"),
                    "max_uses": .integer(maxWebSearches),
                ])
            ])
        }

        do {
            let response: Response = try await SupabaseService.shared.client.functions
                .invoke("claude", options: FunctionInvokeOptions(body: payload))
            return response
        } catch let FunctionsError.httpError(code: code, data: data) {
            // Try to extract a friendly rate-limit message from the body.
            if code == 429 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let err = json["error"] as? [String: Any],
                   let msg = err["message"] as? String {
                    throw ClaudeError.rateLimited(message: msg)
                }
                throw ClaudeError.rateLimited(message: "Rate limit reached.")
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.http(status: code, body: body)
        }
    }

    // MARK: - Discovery (parallel call alongside the main response)

    /// Single buffered Claude call dedicated to community-curated discovery.
    /// Runs in parallel with the main streaming response — its output is a
    /// JSON-only array of additional `CampsiteDTO`s sourced via web_search.
    /// Drift here only affects the supplementary list; the user's primary
    /// MSG+JSON response is untouched.
    ///
    /// Returns an empty array on parse failure or web_search hiccup — caller
    /// (SearchView) treats that as "no extra cards" rather than an error.
    func discoverCampsites(
        query: String,
        lat: Double,
        lng: Double,
        tags: [String] = [],
        limit: Int = 8
    ) async -> [CampsiteDTO] {
        do {
            let resp = try await send(
                model: "claude-haiku-4-5-20251001",
                maxTokens: 2500,
                system: DiscoveryPrompt.systemPrompt,
                userPrompt: DiscoveryPrompt.buildUserPrompt(
                    query: query,
                    lat: lat,
                    lng: lng,
                    tags: tags,
                    limit: limit
                ),
                maxWebSearches: 1
            )
            let parsed = CampsiteParser.parse(resp.text, expectsJSON: true)
            return parsed.sites
        } catch {
            // Quiet failure — discovery is supplementary, never fatal.
            return []
        }
    }

    // MARK: - Streaming

    /// Streaming counterpart to `send`. Yields `.delta(String)` events as
    /// Claude generates text — caller updates UI as chunks arrive — and a
    /// final `.complete(fullText:)` event with the entire raw response so the
    /// caller can run the existing `CampsiteParser` on it.
    ///
    /// Goes through the `claude` Edge Function with `stream: true` in the
    /// body. The function forwards Anthropic's SSE response. We bypass the
    /// Supabase SDK's `functions.invoke` (buffer-only) and use a raw
    /// URLSession bytes stream.
    enum StreamEvent: Sendable {
        case delta(String)        // incremental text chunk
        case complete(String)     // final full text (after stream end)
    }

    func sendStream(
        model: String,
        maxTokens: Int,
        system: String? = nil,
        history: [ChatMessage] = [],
        userPrompt: String,
        maxWebSearches: Int = 0
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runStream(
                        model: model,
                        maxTokens: maxTokens,
                        system: system,
                        history: history,
                        userPrompt: userPrompt,
                        maxWebSearches: maxWebSearches,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func runStream(
        model: String,
        maxTokens: Int,
        system: String?,
        history: [ChatMessage],
        userPrompt: String,
        maxWebSearches: Int,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        // Build the same payload as `send`, plus stream:true.
        let trimmed = history.suffix(12)
        var messages: [[String: Any]] = []
        for msg in trimmed {
            let role = msg.role == .user ? "user" : "assistant"
            let content = msg.claudeText ?? msg.text
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            messages.append(["role": role, "content": content])
        }
        messages.append(["role": "user", "content": userPrompt])

        var payload: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": messages,
            "stream": true,
        ]
        if let system { payload["system"] = system }
        if maxWebSearches > 0 {
            payload["tools"] = [[
                "type": "web_search_20250305",
                "name": "web_search",
                "max_uses": maxWebSearches,
            ]]
        }

        let url = SupabaseService.projectURL.appending(path: "/functions/v1/claude")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // Auth: prefer the user's JWT (so owner-bypass works); fall back to
        // the publishable key when signed out.
        let token: String
        if let session = try? await SupabaseService.shared.client.auth.session {
            token = session.accessToken
        } else {
            token = SupabaseService.publishableKey
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseService.publishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.malformedResponse
        }
        if http.statusCode == 429 {
            throw ClaudeError.rateLimited(message: "Rate limit reached. Try again later.")
        }
        guard http.statusCode == 200 else {
            // Try to read the error body for context.
            var bodyText = ""
            for try await line in bytes.lines {
                bodyText += line + "\n"
                if bodyText.count > 1000 { break }
            }
            throw ClaudeError.http(status: http.statusCode, body: bodyText)
        }

        // Parse Anthropic SSE: each event is `event: <name>\ndata: <json>\n\n`.
        // We only care about `content_block_delta` with `delta.type == "text_delta"`.
        var fullText = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            // Anthropic's stream interleaves event/data lines. We only need
            // `data:` lines — they carry the JSON payload.
            guard line.hasPrefix("data: ") else { continue }
            let payloadStr = String(line.dropFirst(6))
            if payloadStr == "[DONE]" { break }
            guard let data = payloadStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            // Surface text deltas; ignore everything else (tool_use deltas,
            // ping events, message_start/stop frames) for streaming UX.
            if let type = obj["type"] as? String, type == "content_block_delta",
               let delta = obj["delta"] as? [String: Any],
               (delta["type"] as? String) == "text_delta",
               let chunk = delta["text"] as? String, !chunk.isEmpty {
                fullText += chunk
                continuation.yield(.delta(chunk))
            }
        }
        continuation.yield(.complete(fullText))
    }
}

// MARK: - Query classification (port of app.html:3348-3349)

enum QueryKind { case appQuestion, route, location }

func classifyQuery(_ query: String) -> QueryKind {
    let q = query.lowercased()

    // App-question / conversational kind. Includes condition/closure/alert
    // questions ("anything closed in Zion?", "fire bans right now?") — those
    // need a conversational answer + web_search, NOT a JSON campsite list.
    let appQuestion = #"(^|\s)(what can|how do|how does|how to|what is|what are|what do|who are|tell me|explain|help me|features|capabilities|can you|do you|are you|how work|nomadai|about you|about this|where is|what.s in|good time|best time|weather in|things to do|near.*what|recommend|suggest|tips for|far from|drive.*from|distance|closed|closure|fire ban|fire restriction|active alert|any alert|road condition|currently open)"#
    if q.range(of: appQuestion, options: .regularExpression) != nil {
        return .appQuestion
    }

    let route = #"along|on the way|on my way|en route|between .* and|from .* to|drive.*through|road trip|highway|interstate|\bI-\d|\bUS-\d|\bhwy\b|\broute\b.*\d"#
    if q.range(of: route, options: .regularExpression) != nil {
        return .route
    }

    return .location
}

/// Returns true when the query reads like the user wants current / real-time
/// information — closures, fire bans, conditions, alerts, recent reports.
/// Used to gate `maxWebSearches`: 1 for typical queries (Claude rarely fires
/// the tool), 3 for these (Claude is encouraged to look things up).
func queryNeedsLiveData(_ query: String) -> Bool {
    let q = query.lowercased()
    let pattern = #"closed|closure|fire ban|fire restriction|active alert|any alert|road condition|currently|right now|today|this season|recent|latest"#
    return q.range(of: pattern, options: .regularExpression) != nil
}

// MARK: - Model selection per query kind

extension ClaudeService {
    static func model(for kind: QueryKind) -> String {
        // Haiku 4.5 across the board now. Routes used to use Sonnet 4.6 because
        // the prompt asked for fully-optimized multi-stop ordering — heavy
        // reasoning. The new flow asks for unordered candidate stops only, so
        // Haiku handles it fine and finishes ~3x faster.
        return "claude-haiku-4-5-20251001"
    }

    static func maxTokens(for kind: QueryKind) -> Int {
        switch kind {
        // Tightened from 8000/3000/4000 — Claude rarely needs that much room
        // for the typical response shape (10-12 candidate sites JSON for route,
        // 6-10 for location, a paragraph for appQuestion). Faster generation +
        // no observed truncation in normal prompts.
        case .route: return 5000
        case .appQuestion: return 1500
        case .location: return 2500
        }
    }
}
