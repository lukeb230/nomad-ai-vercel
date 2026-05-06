//
//  CampsiteParser.swift
//  Shared parser for Claude responses that contain `MSG: …` + a JSON array of
//  campsites. Used by SearchView (AI / location / route prompts) and by
//  CampsiteService.search() (Map "Search this area" + Search → Location mode).
//

import Foundation
import OSLog

private let parseLog = Logger(subsystem: "LukeBrowne.NomadAI", category: "claude-parse")

enum CampsiteParser {
    struct Parsed {
        var message: String
        var sites: [CampsiteDTO]
    }

    /// Strips an optional `<planning>...</planning>` reasoning block, extracts the
    /// `MSG: <one liner>` headline, then decodes a `[CampsiteDTO]` from the first
    /// `[…]` JSON slice. `expectsJSON = false` (app-question kind) returns the
    /// message only and skips JSON decode.
    static func parse(_ raw: String, expectsJSON: Bool) -> Parsed {
        // Pre-clean: Anthropic's web_search tool wraps cited spans in
        // `<cite index="…">…</cite>` markup. Strip the tags everywhere up
        // front so they don't end up in the JSON-decoded description fields.
        var text = stripCitations(raw)

        // 1. Strip planning block — use the LAST </planning> in case Claude
        //    opened multiple thinking blocks. Anything before it is throwaway.
        if let r = text.range(of: "</planning>", options: .backwards) {
            text = String(text[r.upperBound...])
        }

        // 2. Extract MSG: line.
        var message = ""
        if let msgRange = text.range(of: "MSG:") {
            let after = text[msgRange.upperBound...]
            let line = after.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
            message = line
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .replacingOccurrences(of: "</planning>", with: "")
                .replacingOccurrences(of: "<planning>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Drop anything after a stray "[" if Claude crammed JSON onto the MSG line.
            if let bracket = message.firstIndex(of: "[") {
                message = String(message[..<bracket]).trimmingCharacters(in: .whitespaces)
            }
        }

        if !expectsJSON {
            return Parsed(message: message.isEmpty ? text : message, sites: [])
        }

        // 3. Slice between first [ and last ] and decode.
        guard let firstBracket = text.firstIndex(of: "["),
              let lastBracket = text.lastIndex(of: "]"),
              firstBracket < lastBracket else {
            parseLog.error("no JSON brackets found; raw (first 600): \(String(text.prefix(600)), privacy: .public)")
            return Parsed(message: message, sites: [])
        }
        let jsonSlice = String(text[firstBracket...lastBracket])
        guard let data = jsonSlice.data(using: .utf8) else {
            parseLog.error("slice→data failed; slice (first 600): \(String(jsonSlice.prefix(600)), privacy: .public)")
            return Parsed(message: message, sites: [])
        }
        do {
            let sites = try JSONDecoder().decode([CampsiteDTO].self, from: data)
            return Parsed(message: message, sites: sites)
        } catch {
            parseLog.error("decode error: \(error.localizedDescription); slice (first 600): \(String(jsonSlice.prefix(600)), privacy: .public)")
            return Parsed(message: message, sites: [])
        }
    }

    /// Removes Anthropic web_search citation markup. The opening tag has variable
    /// attributes so we match it with a regex; the closing tag is a literal string.
    /// Inner cited text is preserved.
    private static func stripCitations(_ s: String) -> String {
        var out = s.replacingOccurrences(
            of: #"<cite\b[^>]*>"#,
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(of: "</cite>", with: "")
        return out
    }
}
