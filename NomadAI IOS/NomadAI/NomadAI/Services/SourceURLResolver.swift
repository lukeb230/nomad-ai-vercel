//
//  SourceURLResolver.swift
//  Builds the URL the "Source" button on a CampsiteCard should open.
//
//  The chain is strict-by-default. Claude routinely returns URLs that 404 or
//  point at typo-squat domains; opening those is worse UX than a deterministic
//  search result. The resolver walks four ordered steps and returns the first
//  hit. There's no "no link" outcome — the final step is a Google search of
//  source + name + state, so every card always has a working Source button.
//
//  Order of preference:
//    (a) Trusted explicit URL — campsite.url whose host matches the
//        TRUSTED_HOSTS allowlist (recreation.gov, thedyrt.com, etc.).
//    (b) Source-specific synthesized URL — built from `externalId` for
//        recreation.gov, or from a sane search endpoint for the other major
//        community databases.
//    (c) Google fallback — `<sourceLabel> <name> <city, state>`.
//
//  Untrusted hosts in `campsite.url` are deliberately discarded. The risk
//  isn't security so much as correctness — Claude hallucinates URLs, and
//  search synthesis lands on a real page, where a hallucinated URL doesn't.
//

import Foundation

enum SourceURLResolver {
    /// Hosts whose explicit URLs we trust enough to open verbatim. Subdomains
    /// of these are also accepted (e.g. `www.recreation.gov`). Anything else
    /// in `campsite.url` falls through to synthesis.
    private static let trustedHosts: Set<String> = [
        "recreation.gov",
        "thedyrt.com",
        "ioverlander.com",
        "campendium.com",
        "freecampsites.net",
        "blm.gov",
        "fs.usda.gov",
        "nps.gov",
        "openstreetmap.org",
        "wikipedia.org"
    ]

    /// Returns a URL that's safe to open for the given campsite. Never nil —
    /// the chain ends in a Google search synthesis.
    static func resolve(for site: Campsite) -> URL {
        if let trusted = trustedExplicitURL(site.url) {
            return trusted
        }
        if let synthesized = sourceSpecificURL(for: site) {
            return synthesized
        }
        return googleSearchURL(for: site)
    }

    // MARK: - (a) Trusted explicit URL

    private static func trustedExplicitURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty,
              let url = URL(string: raw),
              let host = url.host?.lowercased(),
              hostIsTrusted(host)
        else { return nil }
        return url
    }

    private static func hostIsTrusted(_ host: String) -> Bool {
        if trustedHosts.contains(host) { return true }
        // Match subdomains: `www.recreation.gov` → `recreation.gov`.
        return trustedHosts.contains { host.hasSuffix(".\($0)") }
    }

    // MARK: - (b) Source-specific synthesis

    private static func sourceSpecificURL(for site: Campsite) -> URL? {
        switch site.source {
        case .recreationGov:
            // FacilityID maps directly to a canonical campground URL. When
            // we don't have it (Claude-only sites), fall back to an in-site
            // search — still better than a 404.
            if let id = site.externalId, !id.isEmpty {
                return URL(string: "https://www.recreation.gov/camping/campgrounds/\(id)")
            }
            return URL(string: "https://www.recreation.gov/search?q=\(encoded(site.name))")

        case .dyrt:
            let q = encoded(joined(site.name, site.state))
            return URL(string: "https://thedyrt.com/search?query=\(q)")

        case .ioverlander:
            // iOverlander's public search is keyword-based via the main map.
            return URL(string: "https://www.ioverlander.com/places?query=\(encoded(site.name))")

        case .campendium:
            let q = encoded(joined(site.name, site.state))
            return URL(string: "https://www.campendium.com/search?q=\(q)")

        case .blm:
            // BLM has no usable site search; route to a site-scoped Google
            // query instead. Lands on the real BLM field-office page in
            // ~95% of overlander searches.
            let q = encoded("site:blm.gov \(joined(site.name, site.state))")
            return URL(string: "https://www.google.com/search?q=\(q)")

        case .other:
            // No idea what source this is — bail and let the Google fallback
            // (which uses sourceLabel) handle it.
            return nil
        }
    }

    // MARK: - (c) Google fallback

    private static func googleSearchURL(for site: Campsite) -> URL {
        var parts: [String] = []
        if !site.sourceLabel.isEmpty, site.sourceLabel.lowercased() != "other" {
            parts.append(site.sourceLabel)
        }
        parts.append(site.name)
        if let city = site.city, !city.isEmpty { parts.append(city) }
        if let state = site.state, !state.isEmpty { parts.append(state) }
        let q = encoded(parts.joined(separator: " "))
        return URL(string: "https://www.google.com/search?q=\(q)")
            ?? URL(string: "https://www.google.com")!
    }

    // MARK: - Utilities

    private static func joined(_ a: String, _ b: String?) -> String {
        guard let b, !b.isEmpty else { return a }
        return "\(a) \(b)"
    }

    private static func encoded(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}
