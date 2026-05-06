//
//  SearchResultsStore.swift
//  Process-wide store so Search tab state survives navigation.
//
//  SearchView's @State was destroyed when the tab dismounted; results,
//  chat history, and the AI note now live here so switching tabs and
//  returning preserves what the user was looking at.
//

import Foundation

@Observable
final class SearchResultsStore {
    static let shared = SearchResultsStore()

    var results: [Campsite] = []
    /// Cards from the parallel community-pick discovery call (Dyrt,
    /// iOverlander, Campendium, overlanding blogs). Rendered as a separate
    /// "FROM THE COMMUNITY" section below `results` so users can tell which
    /// recommendations are NomadAI-curated vs web_search-sourced.
    var discoveryResults: [Campsite] = []
    var aiNote: AINote? = nil
    /// Chat messages exclude the static welcome — that's now rendered as a
    /// dedicated `WelcomeCard` view above the chat scroll.
    var messages: [ChatMessage] = []
    /// True while a parallel discovery (community-pick web_search) call is
    /// running for the current query. Drives the "FINDING COMMUNITY PICKS…"
    /// indicator under the result list. Cleared when the discovery call
    /// completes or fails.
    var discoveryInFlight: Bool = false

    private init() {}
}
