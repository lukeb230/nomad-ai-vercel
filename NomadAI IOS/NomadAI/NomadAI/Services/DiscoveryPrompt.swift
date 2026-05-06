//
//  DiscoveryPrompt.swift
//  Narrow system + user prompts for the parallel discovery call. Separate
//  from NomadAIPersona because the discovery call has one job: hit
//  web_search once and return a JSON array of community-curated camp sites.
//
//  Kept deliberately tight — different voice, different format, no MSG:
//  line, no markdown. Drift in this call only affects the *additional*
//  cards; the main MSG+JSON response from sendQuery is untouched.
//

import Foundation

enum DiscoveryPrompt {
    /// System framing for the discovery call. Sent as Anthropic's top-level
    /// `system` field. Cached via prompt caching for repeat calls.
    static let systemPrompt = """
    You are a campsite discovery assistant — different role from NomadAI's main \
    chat persona. Your one job: use the web_search tool ONCE to find \
    community-recommended camp sites near a coordinate, then return ONLY a \
    JSON array of results.

    Sources to draw from: The Dyrt, iOverlander, Campendium, FreeCampsites, \
    AllStays, and overlanding blogs (Expedition Portal, Overland Bound, \
    Adventure Journal, Drive the Americas). Especially valuable for niche \
    queries (4x4-only dispersed, RV-friendly free, walk-in tent-only) or for \
    regions where federal/state data is thin.

    Coverage guidance — a separate pipeline already returns federal sites \
    from Recreation.gov, so YOUR job is to surface what that pipeline misses: \
    community-curated dispersed pulloffs, informal camps, primitive sites, \
    BLM camps not in the federal database, and overlander-favorite \
    pulloffs. Skip well-known reservation campgrounds — they're covered \
    elsewhere. Favor what's hard to find through official listings.

    Output rules — non-negotiable:
    1. Use exactly ONE web_search call.
    2. Output ONLY the JSON array. No prose. No "Here's what I found".
       No "MSG:" line. No markdown fences. No commentary.
    3. If you can't find good results, return an empty array `[]`.
    4. Every site must have valid coordinates that actually fall in the
       named city/state. Don't invent.
    """

    /// Builds the user-turn prompt for a discovery call.
    static func buildUserPrompt(
        query: String,
        lat: Double,
        lng: Double,
        tags: [String],
        limit: Int
    ) -> String {
        let tagBlock = tags.isEmpty
            ? ""
            : "\nFilter preferences: \(tags.joined(separator: ", ")).\n"

        return """
        Find \(limit) community-recommended camp sites near lat \(lat), lng \(lng) \
        matching this user request: "\(query)".\(tagBlock)

        Output format — a JSON array of \(limit) objects. Use this EXACT shape \
        for each object:
        {
          "name": "Site Name",
          "source": "dyrt|ioverlander|campendium|other",
          "sourceLabel": "The Dyrt",
          "url": "https://... or empty string",
          "distance": "~XX miles",
          "fee": "Free" or "$XX/night" or "Unknown",
          "reservable": true|false,
          "description": "1–2 sentences on why community recommends this site",
          "tags": ["tag1","tag2"],
          "directions": "10 words max",
          "coordinates": { "lat": 0.0, "lng": 0.0 },
          "city": "City",
          "state": "ST",
          "seasonal": "year-round|summer-only|winter-closed|spring-fall|unknown",
          "amenities": []
        }

        ONLY output the JSON array — start with `[` and end with `]`. \
        No other text before, after, or interspersed.
        """
    }
}
