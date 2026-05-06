//
//  SupabaseService.swift
//  Single source of truth for the Supabase client.
//
//  The publishable (anon) key is designed to ship in the binary; Row-Level
//  Security policies on the backend handle per-user access. The Anthropic key
//  by contrast is server-side-only (see ClaudeService) and never lives here.
//
//  We supply a custom encoder/decoder so the Codable DTOs can use camelCase
//  Swift property names (e.g. `userId`) while the database has snake_case
//  columns (e.g. `user_id`). Postgres timestamptz also returns 6-digit
//  microsecond fractions which ISO8601DateFormatter rejects — we truncate to
//  3 digits so it parses cleanly.
//

import Foundation
import Supabase

actor SupabaseService {
    static let shared = SupabaseService()

    /// Project URL — exposed so streaming code paths can build URLs manually
    /// (the Supabase SDK's `functions.invoke` is buffered-only).
    static let projectURL = URL(string: "https://gcvyzunlihlnjmhkwkbz.supabase.co")!

    /// Publishable key — safe to ship in the binary; RLS handles per-user
    /// access. Exposed for streaming code paths (auth header on raw URLSession
    /// requests) when no user JWT is available.
    static let publishableKey = "sb_publishable_dlYojKNrPU7VsdQvFkrGRw_-gNymRID"

    let client: SupabaseClient

    private init() {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)

            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: s) { return d }

            // PostgreSQL emits microseconds (6 fractional digits); truncate to 3.
            if let dotIdx = s.firstIndex(of: ".") {
                var endIdx = s.index(after: dotIdx)
                while endIdx < s.endIndex, s[endIdx].isNumber {
                    endIdx = s.index(after: endIdx)
                }
                let fractional = s[s.index(after: dotIdx)..<endIdx]
                if fractional.count > 3 {
                    let trimmed = s[s.startIndex...dotIdx] + fractional.prefix(3) + s[endIdx...]
                    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let d = iso.date(from: String(trimmed)) { return d }
                }
            }

            throw DecodingError.dataCorruptedError(
                in: try dec.singleValueContainer(),
                debugDescription: "Cannot parse date: \(s)"
            )
        }

        let options = SupabaseClientOptions(
            db: SupabaseClientOptions.DatabaseOptions(
                encoder: encoder,
                decoder: decoder
            )
        )

        self.client = SupabaseClient(
            supabaseURL: Self.projectURL,
            supabaseKey: Self.publishableKey,
            options: options
        )
    }
}
