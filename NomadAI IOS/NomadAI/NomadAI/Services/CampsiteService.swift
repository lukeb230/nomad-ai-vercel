//
//  CampsiteService.swift
//  Coordinate-based campsite search. Claude is the orchestrator — it picks the
//  right mix (federal, dispersed, BLM, state parks, private, primitive) for the
//  user's query. Reference data sources at its disposal:
//
//    • RIDB (Recreation.gov)   — federal campgrounds, authoritative
//    • OSM Overpass            — community-tagged nodes/ways (state parks,
//                                 dispersed, primitive, international)
//
//  Both are fetched in parallel, merged + deduped, passed to Claude as REFERENCE
//  grounding so any sites Claude chooses to mention have accurate names and
//  coordinates. Claude is free to add private campgrounds, dispersed BLM beyond
//  what's tagged, etc. from its own knowledge.
//
//  Photos still flow through the Supabase Edge Function `places`. Weather is
//  Apple WeatherKit (see Services/WeatherCache.swift).
//

import Foundation
import CoreLocation
import Supabase
import OSLog

private let searchLog = Logger(subsystem: "LukeBrowne.NomadAI", category: "campsite-search")

actor CampsiteService {
    static let shared = CampsiteService()

    /// Search for campsites near a point. Always goes through Claude so
    /// natural-language tags / source preferences are honored. RIDB + OSM are
    /// fetched in parallel and passed as reference grounding.
    func search(
        lat: Double,
        lng: Double,
        radius: Int = 50,
        limit: Int = 20,
        tags: [String] = [],
        source: String? = nil
    ) async throws -> [CampsiteDTO] {
        let reference = await fetchReferenceNearby(lat: lat, lng: lng, radius: max(radius, 100), limit: 30)

        let prompt = buildPrompt(
            lat: lat, lng: lng, radius: radius, limit: limit,
            tags: tags, source: source, referenceContext: reference
        )
        let resp = try await ClaudeService.shared.send(
            model: ClaudeService.model(for: .location),
            maxTokens: ClaudeService.maxTokens(for: .location),
            system: NomadAIPersona.systemPrompt,
            userPrompt: prompt,
            // Location mode is structured (UI chips), no live-data intent.
            // Skip the tool definition entirely to save tokens + latency.
            maxWebSearches: 0
        )
        let parsed = CampsiteParser.parse(resp.text, expectsJSON: true)
        searchLog.notice("claude returned \(parsed.sites.count) sites (\(reference.count) reference sites available)")
        return parsed.sites
    }

    /// Fetch known sites near a point from all reference sources (RIDB + OSM)
    /// in parallel, merged and deduped. Used internally and by the AI chat
    /// flow as grounding context. Fail-soft per source — if RIDB hiccups, OSM
    /// still flows through; if both fail, Claude still produces results.
    func fetchReferenceNearby(lat: Double, lng: Double, radius: Int = 100, limit: Int = 30) async -> [CampsiteDTO] {
        async let ridbTask = fetchRIDBSafe(lat: lat, lng: lng, radius: radius, limit: limit)
        async let osmTask  = fetchOSMSafe(lat: lat, lng: lng, radius: radius, limit: limit)
        let (ridb, osm) = await (ridbTask, osmTask)
        searchLog.notice("reference fetch — ridb=\(ridb.count) osm=\(osm.count)")
        return mergeReference(ridb: ridb, osm: osm).prefix(limit).map { $0 }
    }

    // MARK: - Reference cache

    /// Per-source TTL for the in-memory reference cache. RIDB data is stable
    /// (federal facility records change rarely) so cache aggressively. OSM
    /// edits are more frequent but still slow; 12h is plenty.
    private static let ridbTTL: TimeInterval = 24 * 60 * 60   // 24h
    private static let osmTTL:  TimeInterval = 12 * 60 * 60   // 12h

    /// Lat/lng bucket size in degrees. Queries within ~7 miles of a previous
    /// lookup hit the cache. Big enough to dedupe wandering inside a single
    /// area (panning Map, refining a search), small enough that distant
    /// queries always hit the network.
    private static let bucketDegrees: Double = 0.1

    private struct CacheKey: Hashable {
        let latBucket: Int   // round(lat / bucketDegrees)
        let lngBucket: Int
        let radius: Int
        let limit: Int

        init(lat: Double, lng: Double, radius: Int, limit: Int) {
            self.latBucket = Int((lat / bucketDegrees).rounded())
            self.lngBucket = Int((lng / bucketDegrees).rounded())
            self.radius = radius
            self.limit = limit
        }
    }

    private struct CacheEntry {
        let dtos: [CampsiteDTO]
        let storedAt: Date
        func isFresh(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(storedAt) < ttl
        }
    }

    private var ridbCache: [CacheKey: CacheEntry] = [:]
    private var osmCache:  [CacheKey: CacheEntry] = [:]

    private func fetchRIDBSafe(lat: Double, lng: Double, radius: Int, limit: Int) async -> [CampsiteDTO] {
        let key = CacheKey(lat: lat, lng: lng, radius: radius, limit: limit)
        if let entry = ridbCache[key], entry.isFresh(ttl: Self.ridbTTL) {
            searchLog.debug("ridb cache hit (\(entry.dtos.count) sites)")
            return entry.dtos
        }
        do {
            let dtos = try await fetchRIDB(lat: lat, lng: lng, radius: radius, limit: limit)
            ridbCache[key] = CacheEntry(dtos: dtos, storedAt: Date())
            return dtos
        } catch {
            searchLog.error("ridb fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func fetchOSMSafe(lat: Double, lng: Double, radius: Int, limit: Int) async -> [CampsiteDTO] {
        let key = CacheKey(lat: lat, lng: lng, radius: radius, limit: limit)
        if let entry = osmCache[key], entry.isFresh(ttl: Self.osmTTL) {
            searchLog.debug("osm cache hit (\(entry.dtos.count) sites)")
            return entry.dtos
        }
        do {
            let dtos = try await fetchOSM(lat: lat, lng: lng, radius: radius, limit: limit)
            osmCache[key] = CacheEntry(dtos: dtos, storedAt: Date())
            return dtos
        } catch {
            searchLog.error("osm fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Calls the `search-campsites` Edge Function (live RIDB).
    private func fetchRIDB(lat: Double, lng: Double, radius: Int, limit: Int) async throws -> [CampsiteDTO] {
        let payload: [String: AnyJSON] = [
            "lat": .double(lat),
            "lng": .double(lng),
            "radius": .integer(radius),
            "limit": .integer(limit),
        ]
        let dtos: [CampsiteDTO] = try await SupabaseService.shared.client.functions
            .invoke("search-campsites", options: FunctionInvokeOptions(body: payload))
        return dtos
    }

    /// Calls the `osm-campsites` Edge Function (live Overpass).
    private func fetchOSM(lat: Double, lng: Double, radius: Int, limit: Int) async throws -> [CampsiteDTO] {
        let payload: [String: AnyJSON] = [
            "lat": .double(lat),
            "lng": .double(lng),
            "radius": .integer(radius),
            "limit": .integer(limit),
        ]
        let dtos: [CampsiteDTO] = try await SupabaseService.shared.client.functions
            .invoke("osm-campsites", options: FunctionInvokeOptions(body: payload))
        return dtos
    }

    /// RIDB sites first (more authoritative for federal facilities), then OSM
    /// entries that don't look like a duplicate. Dedupe is loose: same name
    /// prefix (12 chars) + within 0.5 mi.
    private func mergeReference(ridb: [CampsiteDTO], osm: [CampsiteDTO]) -> [CampsiteDTO] {
        let key: (CampsiteDTO) -> String = { dto in
            let n = String(dto.name.lowercased().prefix(12)).trimmingCharacters(in: .whitespaces)
            let lat = dto.coordinates.map { String(format: "%.2f", $0.lat) } ?? "?"
            let lng = dto.coordinates.map { String(format: "%.2f", $0.lng) } ?? "?"
            return "\(n)|\(lat)|\(lng)"
        }
        var seen = Set(ridb.map(key))
        var out = ridb
        for dto in osm where !seen.contains(key(dto)) {
            seen.insert(key(dto))
            out.append(dto)
        }
        return out
    }

    private func buildPrompt(
        lat: Double,
        lng: Double,
        radius: Int,
        limit: Int,
        tags: [String],
        source: String?,
        referenceContext: [CampsiteDTO]
    ) -> String {
        var preferences: [String] = []
        if !tags.isEmpty {
            preferences.append("Prefer types: \(tags.joined(separator: ", "))")
        }
        if let source, !source.isEmpty {
            preferences.append("Prefer source: \(source)")
        }
        let prefBlock = preferences.isEmpty ? "" : "\n\(preferences.joined(separator: "\n"))\n"
        let groundingBlock = referenceContextBlock(referenceContext)

        return """
        Find up to \(limit) real campsites within ~\(radius) miles of lat \(lat), lng \(lng).
        \(prefBlock)
        \(groundingBlock)
        Respond in this EXACT format:

        MSG: <one friendly sentence, max 15 words>
        <newline>
        <JSON array of \(limit) campsites>

        Each campsite object MUST have these keys:
        {
          "name": "Site Name",
          "source": "dyrt|recreation.gov|ioverlander|blm|campendium|other",
          "sourceLabel": "Display label",
          "url": "https://... or empty string",
          "distance": "~XX miles",
          "fee": "Free" or "$XX/night" or "Unknown",
          "reservable": true|false,
          "description": "1–2 sentences",
          "tags": ["tag1","tag2"],
          "directions": "10 words max",
          "coordinates": { "lat": 0.0, "lng": 0.0 },
          "city": "City",
          "state": "ST",
          "seasonal": "year-round|summer-only|winter-closed|spring-fall|unknown",
          "amenities": []
        }

        Coordinate accuracy is critical: every lat/lng must actually fall within ~\(radius) miles of the query point and match the city/state fields.
        """
    }

    /// Reference-only grounding block. Neutral framing: this is data Claude
    /// can verify against IF it mentions any of these sites. It isn't a
    /// required list and shouldn't bias selection across the source mix.
    private func referenceContextBlock(_ sites: [CampsiteDTO]) -> String {
        guard !sites.isEmpty else { return "" }
        let lines = sites.prefix(30).enumerated().map { i, s -> String in
            let coords = s.coordinates.map { "lat \($0.lat), lng \($0.lng)" } ?? "no coords"
            let url = s.url?.isEmpty == false ? " — \(s.url!)" : ""
            let label = s.sourceLabel ?? s.source
            return "\(i + 1). \(s.name) [\(label)] (\(coords))\(url)"
        }
        return """

        Reference — known campsites near this location (Recreation.gov + OpenStreetMap):
        \(lines.joined(separator: "\n"))

        These are facts you can verify against, not a required list. Recommend \
        whatever genuinely fits the user's request — dispersed, BLM, state parks, \
        private, primitive, or federal — drawing from your full knowledge. If you \
        do mention a site that's on this reference list, copy its name and \
        coordinates exactly.

        """
    }
}

// MARK: - Photo fetching via Supabase Edge Function `places`

actor PlacesService {
    static let shared = PlacesService()

    private let baseURL = URL(string: "https://gcvyzunlihlnjmhkwkbz.supabase.co/functions/v1")!

    /// Fetch up to 5 photo references for a campsite name.
    func searchPhotoReferences(for siteName: String) async throws -> [String] {
        var components = URLComponents(url: baseURL.appending(path: "/places"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "type", value: "search"),
            URLQueryItem(name: "input", value: siteName)
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)

        struct Envelope: Codable {
            let candidates: [Candidate]
            struct Candidate: Codable {
                let photos: [Photo]?
                struct Photo: Codable {
                    let photo_reference: String
                }
            }
        }
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        return env.candidates.first?.photos?.map(\.photo_reference) ?? []
    }

    /// Returns a URL pointing at the proxied photo. Use directly with AsyncImage.
    /// The `places` Edge Function is deployed with --no-verify-jwt so AsyncImage
    /// can GET this URL without an Authorization header.
    func photoURL(reference: String) -> URL {
        baseURL
            .appending(path: "/places")
            .appending(queryItems: [
                URLQueryItem(name: "type", value: "photo"),
                URLQueryItem(name: "ref", value: reference)
            ])
    }
}

// Weather lives in WeatherCache.swift now (Apple WeatherKit-backed).
