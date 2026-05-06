//
//  SearchView.swift
//  Tab 2 — AI-as-hero search.
//
//  Spec: docs/screen-inventory.md §2, redesign HTML lines 1595–1736.
//  Business logic: docs/business-logic.md §1–4.
//

import SwiftUI
import SwiftData
import UIKit
import CoreLocation

struct SearchView: View {
    enum Mode { case askAI, location }

    @Environment(\.modelContext) private var ctx

    // Shared, process-wide so it survives tab navigation.
    @State private var store = SearchResultsStore.shared

    @State private var mode: Mode = .askAI

    // AI mode
    @State private var aiInput: String = ""
    @State private var isThinking: Bool = false

    // Location mode
    @State private var locInput: String = ""
    @State private var selectedTypes: Set<String> = ["Dispersed / BLM", "Overlanding"]
    @AppStorage("default_radius") private var selectedRadius: Int = 50
    /// User-controlled toggle (Settings → Search defaults) for the parallel
    /// community-pick discovery call. Default on — the additional cards are
    /// the main reason we built this. Users can disable to save on Claude
    /// quota or if they only trust NomadAI's own curation.
    @AppStorage("discovery_enabled") private var discoveryEnabledSetting: Bool = true

    // Transient — fine to lose on dismount.
    @State private var errorBanner: String? = nil
    @State private var locating: Bool = false
    @State private var keyboardHeight: CGFloat = 0
    /// Non-nil while a streaming Claude response is in flight. Renders as a
    /// temporary AI bubble that grows as text arrives. Cleared once the
    /// stream finishes — final text is then committed as a `ChatMessage`.
    @State private var streamingText: String? = nil
    /// Kind of the in-flight query — drives whether the streaming bubble
    /// hides pre-`MSG:` reasoning (for `.location`/`.route`) or shows raw
    /// text immediately (for `.appQuestion`).
    @State private var streamingKind: QueryKind? = nil
    /// Bumped per `sendQuery`. Both the main stream and the parallel
    /// discovery task capture the value at fan-out time and only merge their
    /// results if it still matches when they finish — protects against a
    /// late-returning discovery from a previous query landing in the wrong
    /// result set.
    @State private var activeQueryID: UUID = UUID()

    @FocusState private var aiInputFocused: Bool
    @FocusState private var locInputFocused: Bool

    @State private var speech = SpeechRecognitionService.shared
    @State private var onboarding = OnboardingFlowState.shared
    @State private var routeBuilder = RouteBuilderState.shared

    private var userLat: Double { LocationService.shared.coordinateOrFallback.latitude }
    private var userLng: Double { LocationService.shared.coordinateOrFallback.longitude }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    topbar
                    hero
                    NPSAlertsBanner()
                    modeTogglePill

                    if let banner = errorBanner {
                        ErrorBanner(text: banner) { errorBanner = nil }
                    }

                    Group {
                        switch mode {
                        case .askAI:    aiPanel
                        case .location: locationPanel
                        }
                    }
                    .id("inputAnchor")

                    if let note = store.aiNote {
                        AINoteView(note: note).padding(.top, 4)
                    }
                    if !store.results.isEmpty {
                        LazyVStack(spacing: 14) {
                            ForEach(store.results) { CampsiteCard(campsite: $0) }
                        }
                        .padding(.top, 6)
                    }
                    if !store.discoveryResults.isEmpty {
                        DiscoverySectionHeader()
                            .padding(.top, store.results.isEmpty ? 6 : 16)
                        LazyVStack(spacing: 14) {
                            ForEach(store.discoveryResults) { CampsiteCard(campsite: $0) }
                        }
                        .padding(.top, 6)
                    }
                    if store.discoveryInFlight {
                        DiscoveryProgressBanner()
                            .padding(.top, 8)
                            .transition(.opacity)
                    }

                    Spacer(minLength: keyboardHeight > 0 ? keyboardHeight + 80 : 100)
                }
                .padding(.horizontal, Spacing.pageHorizontal)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.bg)
            .onChange(of: aiInputFocused) { _, focused in
                if focused { scrollToInput(proxy: proxy) }
            }
            .onChange(of: locInputFocused) { _, focused in
                if focused { scrollToInput(proxy: proxy) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notif in
                if let frame = notif.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    withAnimation(.easeOut(duration: 0.2)) { keyboardHeight = frame.height }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollToInput(proxy: proxy)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.2)) { keyboardHeight = 0 }
            }
            // No device-location NPS refresh on tab open — banner only
            // populates from the dominant state of search results.
        }
    }

    private func scrollToInput(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo("inputAnchor", anchor: .bottom)
        }
    }

    // MARK: - Topbar / Hero / Mode toggle

    private var topbar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Search").monoLabel()
            FrauncesEmphasis(prefix: "Find your ", italic: "spot", suffix: "", size: 22)
        }
        .padding(.top, 18)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("★ Ask freely").monoLabel()
            Text("Plain English. Route queries, vibe queries, beginner questions — all ok.")
                .font(.body(13)).foregroundStyle(.muted)
        }
    }

    private var modeTogglePill: some View {
        HStack(spacing: 2) {
            ModeButton(label: "Ask AI", system: "sparkle", active: mode == .askAI) { mode = .askAI }
            ModeButton(label: "Location", system: "location", active: mode == .location) { mode = .location }
        }
        .padding(4)
        .background(Capsule().fill(Color.bark))
        .overlay(Capsule().strokeBorder(Color.line, lineWidth: 1))
    }

    // MARK: - AI panel

    private var aiPanel: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Welcome + onboarding only render when chat is empty.
                        // Once messages start, they collapse so chat owns the space.
                        if store.messages.isEmpty {
                            WelcomeCard { example in
                                aiInput = example
                                onboarding.dismiss()
                                sendQuery()
                            }
                            if onboarding.step != .complete && onboarding.step != .dismissed {
                                OnboardingFlow(state: onboarding) { synthesizedQuery in
                                    aiInput = synthesizedQuery
                                    sendQuery()
                                }
                            }
                        }

                        // Route builder panel — pinned at top of chat scroll while
                        // a route is being assembled. Disappears when cancelled or
                        // built. Refresh button fires a follow-up query through
                        // the same chat path so conversation context is preserved.
                        RouteBuilderPanel(onMoreOptions: requestMoreRouteOptions)

                        ForEach(store.messages) { msg in
                            ChatBubble(role: msg.role == .user ? .user : .ai, text: msg.text)
                                .id(msg.id)
                        }
                        if let live = streamingText, !live.isEmpty {
                            // For .location/.route queries we suppress the
                            // bubble until Claude emits the MSG: marker, so
                            // pre-MSG reasoning never leaks into the chat.
                            // streamingDisplay returns "" while we should hide
                            // — UI falls back to ThinkingDots in that case.
                            let display = streamingDisplay(live, kind: streamingKind)
                            if !display.isEmpty {
                                ChatBubble(role: .ai, text: display)
                                    .id("streaming")
                            } else {
                                ThinkingDots().id("thinking-prestream")
                            }
                        } else if isThinking || streamingText != nil {
                            // Pre-stream and during web_search pause: typing
                            // dots show progress without leaking placeholder
                            // text. Swaps to the streaming bubble the moment
                            // Claude emits user-facing content.
                            ThinkingDots().id("thinking")
                        }
                    }
                    .padding(16)
                }
                .frame(minHeight: 340, maxHeight: 540)
                .onChange(of: store.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(store.messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: isThinking) { _, thinking in
                    if thinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                }
            }

            Divider().background(Color.line)

            // Input bar
            HStack(spacing: 8) {
                TextField("Ask about campsites…", text: $aiInput, axis: .vertical)
                    .font(.body(14))
                    .lineLimit(1...4)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.surface))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line, lineWidth: 1))
                    .submitLabel(.send)
                    .onSubmit(sendQuery)
                    .focused($aiInputFocused)

                Button(action: toggleVoiceInput) {
                    Image(systemName: speech.isListening ? "mic.fill" : "mic")
                        .frame(width: 44, height: 44)
                        .foregroundStyle(speech.isListening ? Color.berry : Color.fgDim)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(speech.isListening ? Color.berry.opacity(0.5) : Color.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speech.isListening ? "Stop dictation" : "Dictate search query")

                Button(action: sendQuery) {
                    Image(systemName: isThinking ? "ellipsis" : "paperplane.fill")
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Color.clayInk)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.clay))
                        .shadow(color: Color.clay.opacity(0.25), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(aiInput.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
                .opacity(aiInput.trimmingCharacters(in: .whitespaces).isEmpty || isThinking ? 0.5 : 1)
            }
            .padding(12)
            .background(Color.bark)
        }
        .background(Color.bark)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.line, lineWidth: 1))
        .shadowSm()
    }

    // MARK: - Location panel

    private var locationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if LocationService.shared.isDenied {
                LocationDeniedBanner()
            }

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.muted)
                TextField("City, park, or highway…", text: $locInput)
                    .font(.body(14))
                    .submitLabel(.search)
                    .onSubmit(runLocationSearch)
                    .focused($locInputFocused)
                Button(action: requestNearMe) {
                    Group {
                        if locating {
                            ProgressView().controlSize(.small).tint(.muted)
                        } else {
                            Image(systemName: "location.fill").foregroundStyle(.muted)
                        }
                    }
                    .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(locating)
                .accessibilityLabel("Use my location")
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.bark))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line, lineWidth: 1))

            // Type
            FilterSection(label: "Type", note: "multi") {
                FlowLayout(spacing: 6) {
                    ForEach(SearchView.typeOptions, id: \.self) { t in
                        FilterChip(label: t, isOn: selectedTypes.contains(t)) {
                            toggle(&selectedTypes, value: t)
                        }
                    }
                }
            }

            // Radius
            FilterSection(label: "Search radius") {
                HStack(spacing: 6) {
                    ForEach(SearchView.radiusOptions, id: \.self) { r in
                        RadiusChip(value: r, isOn: selectedRadius == r) {
                            selectedRadius = r
                        }
                    }
                }
            }

            // CTA
            Button(action: runLocationSearch) {
                HStack {
                    if isThinking {
                        ProgressView().tint(Color.clayInk)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text(isThinking ? "Searching…" : "Search the field")
                        .font(.body(14, weight: .bold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .foregroundStyle(Color.clayInk)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.clay))
                .shadow(color: Color.clay.opacity(0.3), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(isThinking)
            .opacity(isThinking ? 0.7 : 1)
        }
    }

    static let typeOptions = [
        "Dispersed / BLM",
        "Paid w/ facilities",
        "Overlanding",
        "Walk-up",
        "Reservable",
        "Free",
        "RV friendly",
        "Tent only"
    ]

    static let radiusOptions = [25, 50, 100, 200]

    private func toggle<T: Hashable>(_ set: inout Set<T>, value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    // MARK: - Voice input

    private func toggleVoiceInput() {
        if speech.isListening {
            speech.stopListening()
        } else {
            Task {
                let started = await speech.startListening()
                if !started, let err = speech.error {
                    errorBanner = err
                }
            }
        }
    }

    // MARK: - Actions: Near me

    private func requestNearMe() {
        Task {
            locating = true
            defer { locating = false }
            do {
                _ = try await LocationService.shared.requestLocation()
                // No further action — `userLat`/`userLng` now read the live coordinate;
                // any subsequent search picks it up. The denial banner observes
                // `LocationService.shared.isDenied` directly so it auto-clears on grant.
            } catch LocationService.Failure.denied, LocationService.Failure.restricted {
                // Banner self-renders via observation; no local state required.
            } catch {
                errorBanner = "Couldn't get your location. Try again."
            }
        }
    }

    // MARK: - Actions: Location search

    private func runLocationSearch() {
        locInputFocused = false
        Task {
            isThinking = true
            errorBanner = nil
            defer { isThinking = false }
            do {
                let tags = Array(selectedTypes)
                let dtos = try await CampsiteService.shared.search(
                    lat: userLat, lng: userLng,
                    radius: selectedRadius, limit: 20,
                    tags: tags, source: nil
                )
                let upserted = dtos.map { Campsite.upsert(from: $0, into: ctx) }
                try? ctx.save()
                store.results = upserted
                store.aiNote = AINote(
                    label: "\(store.results.count) found within \(selectedRadius) mi",
                    tone: store.results.isEmpty ? .warning : .success
                )
                Task { await validateCoordinates(for: upserted, in: ctx) }
                if let state = dominantState(of: upserted) {
                    Task { await NPSAlertsService.shared.refreshForState(stateCode: state) }
                }
            } catch {
                errorBanner = "Couldn't reach the field. Try again."
                store.aiNote = nil
            }
        }
    }

    /// Append new sites to `store.results`, deduping by `Campsite.id` so
    /// repeated upserts don't double-render the main list.
    @MainActor
    private func mergeIntoResults(_ newSites: [Campsite]) {
        let existing = Set(store.results.map { $0.id })
        let toAppend = newSites.filter { !existing.contains($0.id) }
        guard !toAppend.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            store.results.append(contentsOf: toAppend)
        }
    }

    /// Append discovery cards into the community section, skipping any IDs
    /// already in main results OR already in the discovery section. Main
    /// always wins — a site that's in both gets shown under main only.
    @MainActor
    private func mergeIntoDiscoveryResults(_ newSites: [Campsite]) {
        let blocked = Set(store.results.map(\.id)).union(store.discoveryResults.map(\.id))
        let toAppend = newSites.filter { !blocked.contains($0.id) }
        guard !toAppend.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            store.discoveryResults.append(contentsOf: toAppend)
        }
    }

    /// Returns the most-common state code among results that have one set.
    /// Used to refresh the NPS alerts banner so it reflects what the user
    /// actually searched for (not their device location).
    private func dominantState(of sites: [Campsite]) -> String? {
        let codes = sites.compactMap { $0.state?.uppercased() }.filter { $0.count == 2 }
        guard !codes.isEmpty else { return nil }
        return Dictionary(grouping: codes, by: { $0 })
            .mapValues(\.count)
            .max(by: { $0.value < $1.value })?
            .key
    }

    // MARK: - Actions: Route refresh

    /// Fired by RouteBuilderPanel's "Show more options" button. Drops a brief
    /// follow-up message into the chat and reruns the search. Conversation
    /// history is preserved automatically because we go through the same
    /// `sendQuery` path — Claude sees what it already suggested and varies.
    private func requestMoreRouteOptions() {
        guard !isThinking else { return }
        aiInput = "Show me a different batch of candidate stops along this route — different from what you've shown so far."
        sendQuery()
    }

    // MARK: - Actions: AI search

    private func sendQuery() {
        let q = aiInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isThinking else { return }
        aiInputFocused = false
        aiInput = ""
        store.messages.append(ChatMessage(role: .user, text: q))

        // Bump generation + clear previous results so the merge starts clean.
        // Doing this on the MainActor before the Task fires guarantees the UI
        // doesn't show stale cards while the next response is in flight.
        let queryID = UUID()
        activeQueryID = queryID
        store.results = []
        store.discoveryResults = []
        store.aiNote = nil

        Task {
            isThinking = true
            // Empty streamingText flips the chat to the "Fetching results…"
            // placeholder bubble immediately — user sees activity while we
            // do reference fetch + prompt build + initial Claude latency.
            streamingText = ""
            errorBanner = nil
            defer { isThinking = false }

            let kind = classifyQuery(q)
            let model = ClaudeService.model(for: kind)
            let maxTokens = ClaudeService.maxTokens(for: kind)
            streamingKind = kind

            // Route queries: activate the route-builder flow. Claude returns
            // CANDIDATE stops (not a finished trip); the user picks via the
            // "Add to route" buttons on the cards.
            if kind == .route {
                routeBuilder.start(description: q)
            }

            // Parallel community-pick discovery — fires alongside the main
            // stream rather than after it. Independent buffered Claude call
            // with web_search budget = 1 (Dyrt, iOverlander, Campendium,
            // overlanding blogs). Cards land below main results when ready.
            // Skipped for non-location queries — app questions and route
            // candidates don't benefit from web augmentation.
            //
            // Gated by `discovery_enabled` in Settings (default on). Disabling
            // saves a Claude call per query — the user just sees main results.
            // Fail-quiet on errors so a flaky web_search never blocks main.
            let discoveryEnabled = (kind == .location) && discoveryEnabledSetting
            if discoveryEnabled {
                store.discoveryInFlight = true
                Task { @MainActor in
                    let extras = await ClaudeService.shared.discoverCampsites(
                        query: q, lat: userLat, lng: userLng, limit: 8
                    )
                    // Discard if a newer query has been sent — its own
                    // discovery task owns the store now.
                    guard activeQueryID == queryID else { return }
                    let extraSites = extras.map { Campsite.upsert(from: $0, into: ctx) }
                    try? ctx.save()
                    mergeIntoDiscoveryResults(extraSites)
                    store.aiNote = noteFor(kind: kind, count: store.results.count + store.discoveryResults.count)
                    store.discoveryInFlight = false
                }
            }

            // For location queries, ground Claude in known campsites near the
            // user from all reference sources (RIDB + OSM). Claude weaves them
            // into its response and adds dispersed/private/state-park sites
            // from its own knowledge.
            let referenceContext: [CampsiteDTO]
            if kind == .location {
                referenceContext = await CampsiteService.shared.fetchReferenceNearby(
                    lat: userLat, lng: userLng, radius: 100, limit: 30
                )
            } else {
                referenceContext = []
            }
            let prompt = buildPrompt(query: q, kind: kind, referenceContext: referenceContext)

            // Conversation history = everything BEFORE the latest user turn.
            // The latest user turn goes through `prompt` (format-augmented).
            // For AI turns, claudeText carries the full raw response with JSON
            // so on the next turn Claude can reference what it suggested.
            let history = Array(store.messages.dropLast())

            do {
                // Web search budget per query kind:
                //   • Live-data queries (closures, fire bans, conditions):
                //     up to 3 calls — Claude needs current intel.
                //   • Everything else: 0 — web_search was destabilizing the
                //     strict MSG: + JSON output format. Claude would do the
                //     search and then write a prose summary instead of the
                //     structured response, so cards never landed. Disabling
                //     for .location/.route until we can constrain the format
                //     more reliably with web_search active.
                let webSearches: Int = queryNeedsLiveData(q) ? 3 : 0

                // Stream the response — display text in a transient bubble
                // as it arrives, then run the parser on the final full text.
                // streamingText was set to "" at the top of the Task so the
                // placeholder is already visible.
                var fullText = ""
                let stream = await ClaudeService.shared.sendStream(
                    model: model,
                    maxTokens: maxTokens,
                    system: NomadAIPersona.systemPrompt,
                    history: history,
                    userPrompt: prompt,
                    maxWebSearches: webSearches
                )
                // Race the stream against a wall-clock timeout so a stalled
                // Anthropic connection (or our SSE parser missing the close)
                // can't strand the user staring at a half-rendered bubble.
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await Task.sleep(nanoseconds: 45_000_000_000) // 45s
                        throw URLError(.timedOut)
                    }
                    group.addTask { @MainActor in
                        for try await event in stream {
                            switch event {
                            case .delta(let chunk):
                                streamingText = (streamingText ?? "") + chunk
                            case .complete(let final):
                                fullText = final
                            }
                        }
                    }
                    // First child to finish cancels the other. The stream
                    // task naturally completes on stream end; the timer
                    // throws if it wins.
                    try await group.next()
                    group.cancelAll()
                }
                // Stream done. Clear the transient bubble before committing
                // the final ChatMessage so the UI swap is instant.
                streamingText = nil
                streamingKind = nil

                let parsed = CampsiteParser.parse(fullText, expectsJSON: kind != .appQuestion)
                let aiText = parsed.message.isEmpty
                    ? (kind == .appQuestion ? fullText : "Here's what I found.")
                    : parsed.message
                store.messages.append(ChatMessage(role: .ai, text: aiText, claudeText: fullText))
                guard activeQueryID == queryID else { return }
                let upserted = parsed.sites.map { Campsite.upsert(from: $0, into: ctx) }
                try? ctx.save()
                // Merge instead of replace — the parallel discovery task may
                // have already landed cards in `store.discoveryResults`.
                // mergeIntoResults dedupes by id within the main array.
                mergeIntoResults(upserted)
                // If discovery raced ahead and landed any sites that the
                // main stream also returned, drop those from the discovery
                // section so each card appears in only one section.
                if !store.discoveryResults.isEmpty {
                    let mainIds = Set(store.results.map(\.id))
                    store.discoveryResults.removeAll { mainIds.contains($0.id) }
                }
                store.aiNote = noteFor(kind: kind, count: store.results.count + store.discoveryResults.count)
                Task { await validateCoordinates(for: upserted, in: ctx) }
                if let state = dominantState(of: upserted) {
                    Task { await NPSAlertsService.shared.refreshForState(stateCode: state) }
                }

            } catch ClaudeService.ClaudeError.rateLimited(let msg) {
                streamingText = nil
                streamingKind = nil
                errorBanner = msg
                store.messages.append(ChatMessage(
                    role: .ai,
                    text: "AI search paused — try Location mode for now."
                ))
            } catch {
                streamingText = nil
                streamingKind = nil
                errorBanner = "Something went wrong. Try again."
            }
        }
    }

    /// Strip the JSON tail, `MSG:` prefix, and any markdown fences from the
    /// streaming response so the transient bubble shows just the
    /// conversational sentence as it grows.
    ///
    /// For `.location` / `.route` queries we HIDE pre-MSG content entirely —
    /// Claude often does some pre-amble (acknowledgments, web_search prep,
    /// reasoning) before the structured `MSG:` line. Returning empty here
    /// makes the UI fall back to ThinkingDots instead of leaking that
    /// internal text into the chat. Once `MSG:` arrives, the bubble springs
    /// to life with the actual content.
    ///
    /// For `.appQuestion`, no MSG/JSON format is expected — Claude streams
    /// conversational prose directly, so we surface it immediately.
    private func streamingDisplay(_ raw: String, kind: QueryKind?) -> String {
        var text = raw
        if let r = text.range(of: "</planning>", options: .backwards) {
            text = String(text[r.upperBound...])
        }

        if kind == .location || kind == .route {
            // Hide everything until MSG: shows up.
            guard let msgRange = text.range(of: "MSG:") else { return "" }
            let working = String(text[msgRange.upperBound...])
            return cutAtNonProseMarkers(working)
        }

        // .appQuestion or unknown — show raw stream, just trim the markers.
        return cutAtNonProseMarkers(text)
    }

    /// Truncates at the earliest non-prose marker (markdown fence, JSON
    /// bracket, planning block) and trims whitespace.
    private func cutAtNonProseMarkers(_ s: String) -> String {
        var cut = s.endIndex
        for marker in ["```", "[", "<planning>", "</planning>"] {
            if let r = s.range(of: marker), r.lowerBound < cut {
                cut = r.lowerBound
            }
        }
        return String(s[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt construction

    private func buildPrompt(query: String, kind: QueryKind, referenceContext: [CampsiteDTO] = []) -> String {
        switch kind {
        case .appQuestion:
            return appQuestionPrompt(query: query)
        case .location:
            return locationPrompt(query: query, referenceContext: referenceContext)
        case .route:
            return routePrompt(query: query)
        }
    }

    /// Reference-only grounding block. Reference sources (Recreation.gov, OSM)
    /// are tools in NomadAI's kit, not a default — Claude should still pull
    /// from its full knowledge of dispersed, BLM, private, primitive sites.
    /// The block only exists so that *if* a referenced site is the right
    /// answer, the name and coordinates are accurate.
    private func referenceContextBlock(_ sites: [CampsiteDTO]) -> String {
        guard !sites.isEmpty else { return "" }
        let lines = sites.prefix(30).enumerated().map { idx, s -> String in
            let coords = s.coordinates.map { "lat \($0.lat), lng \($0.lng)" } ?? "no coords"
            let url = s.url?.isEmpty == false ? " — \(s.url!)" : ""
            let label = s.sourceLabel ?? s.source
            return "\(idx + 1). \(s.name) [\(label)] (\(coords))\(url)"
        }
        return """

        Reference — known campsites near the user (Recreation.gov + OpenStreetMap):
        \(lines.joined(separator: "\n"))

        These are facts you can verify against, not a required list. Recommend \
        whatever genuinely fits the user's request — dispersed, BLM, state parks, \
        private, primitive, or federal — drawing from your full knowledge. If you \
        do mention a site that's on this reference list, copy its name and \
        coordinates exactly.

        """
    }

    private func appQuestionPrompt(query: String) -> String {
        """
        Answer the user's question conversationally and concisely (a few sentences max). \
        Do NOT output JSON.

        User question: \(query)
        """
    }

    private func locationPrompt(query: String, referenceContext: [CampsiteDTO]) -> String {
        """
        Find campsites matching the user's request. \
        The user is at approximately lat \(userLat), lng \(userLng).
        \(referenceContextBlock(referenceContext))
        User request: \(query)

        Respond in this EXACT format:

        MSG: <one friendly sentence, max 15 words>
        <newline>
        <JSON array of 6–10 campsites>

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
        """
    }

    private func routePrompt(query: String) -> String {
        let waypoints = extractWaypoints(query)
        let startCity = waypoints.first ?? "the start of the route"
        let endCity = waypoints.last ?? "the end of the route"

        return """
        The user wants to plan a route. DO NOT build a finished, ordered trip — \
        instead, surface a variety of CANDIDATE STOPS along this route so the user \
        can pick which ones to add via the "Add to route" button on each card.

        User request: \(query)

        Suggest 8–12 candidate stops along the corridor between \(startCity) and \(endCity). \
        Mix variety so the user has real choices:
        - Established campgrounds (reservable + walk-up)
        - Dispersed BLM / Forest Service spots
        - Notable scenic stops, hot springs, trailheads, viewpoints
        - Different fee tiers (free + paid)
        - Coverage spread across the route, not bunched at the endpoints

        Each candidate must fall along or within ~30 miles of the route corridor. \
        Don't pre-pick or pre-order — these are options, not a finished itinerary.

        Respond in this EXACT format:

        MSG: <one friendly acknowledgment of the route, max 18 words. Mention that the user \
        can pick which stops to add via the "Add to route" buttons below.>
        <newline>
        <JSON array of 8–12 candidate stops>

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
        """
    }

    /// Extract place names from "from X to Y", "X to Y", "between X and Y".
    private func extractWaypoints(_ query: String) -> [String] {
        let patterns = [
            #"from\s+([A-Za-z][A-Za-z\s,\.]+?)\s+to\s+([A-Za-z][A-Za-z\s,\.]+?)(?:\s+via\s+([A-Za-z][A-Za-z\s,\.]+?))?(?:[\.\!\?,]|$)"#,
            #"between\s+([A-Za-z][A-Za-z\s,\.]+?)\s+and\s+([A-Za-z][A-Za-z\s,\.]+?)(?:[\.\!\?,]|$)"#
        ]
        for p in patterns {
            if let r = query.range(of: p, options: [.regularExpression, .caseInsensitive]) {
                let match = String(query[r])
                let stripped = match
                    .replacingOccurrences(of: "from ", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "between ", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: " via ", with: "|", options: .caseInsensitive)
                    .replacingOccurrences(of: " and ", with: "|", options: .caseInsensitive)
                    .replacingOccurrences(of: " to ", with: "|", options: .caseInsensitive)
                let parts = stripped.split(separator: "|").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                      .trimmingCharacters(in: CharacterSet(charactersIn: ".!?,"))
                }.filter { !$0.isEmpty }
                if parts.count >= 2 { return parts }
            }
        }
        return []
    }

    private func estimateStopCount(query: String, waypoints: Int) -> Int {
        let q = query.lowercased()
        let locs = max(waypoints, 2)
        let base = max(12, locs * 4)
        if q.range(of: #"month|30.?day|four.?week|4.?week"#, options: .regularExpression) != nil {
            return max(base, 16)
        }
        if q.range(of: #"two.?week|2.?week|14.?day"#, options: .regularExpression) != nil {
            return max(base, 14)
        }
        if q.range(of: #"\b(a |one )?week\b|7.?day|seven.?day"#, options: .regularExpression) != nil {
            return max(base, 12)
        }
        if q.range(of: #"weekend|[2-5].?day|two.?day|three.?day|four.?day|five.?day"#, options: .regularExpression) != nil {
            return max(10, locs * 3)
        }
        return base
    }

    private func buildSegmentRules(waypoints: [String]) -> String {
        guard waypoints.count >= 2 else { return "1. SEGMENTS: Distribute stops evenly across the route." }
        let perSegment = max(2, 12 / max(1, waypoints.count - 1))
        let parts = (0..<waypoints.count - 1).map { i in
            "At least \(perSegment) stops geographically BETWEEN \(waypoints[i]) → \(waypoints[i+1])"
        }
        return "1. SEGMENTS: " + parts.joined(separator: "; ")
    }

    // Parser moved to Services/CampsiteParser.swift for reuse with CampsiteService.search.

    private func noteFor(kind: QueryKind, count: Int) -> AINote {
        switch kind {
        case .appQuestion:
            return AINote(label: "Answered in chat", tone: .info)
        case .route:
            return AINote(label: "Route query · \(count) stops", tone: .success)
        case .location:
            return AINote(label: "\(count) campsites found", tone: .success)
        }
    }
}

// MARK: - Discovery section header

/// Visual divider between main results (NomadAI-curated, RIDB/OSM-grounded)
/// and the community-pick cards from the parallel web_search discovery call.
/// Reads as an editorial section break — hairline rules + small mono label —
/// not a heavy heading, so it doesn't compete with the cards visually.
private struct DiscoverySectionHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.line).frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.muted)
                Text("FROM THE COMMUNITY")
                    .font(.mono(10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.muted)
            }
            Rectangle().fill(Color.line).frame(height: 1)
        }
    }
}

// MARK: - Discovery progress banner

/// Shown below the result list while the parallel community-pick discovery
/// call (Dyrt / iOverlander / Campendium / overland blogs) is in flight.
/// Disappears when discovery returns — either with new cards merged in or
/// silently if it found nothing.
private struct DiscoveryProgressBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(.muted)
            Text("FINDING COMMUNITY PICKS…")
                .font(.mono(10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.muted)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.bark))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line, lineWidth: 1))
    }
}

// MARK: - Location denied banner (Search location panel)

private struct LocationDeniedBanner: View {
    var body: some View {
        Button(action: openSettings) {
            HStack(spacing: 6) {
                Image(systemName: "location.slash").font(.system(size: 12))
                Text("Location is off — using Moab.")
                    .font(.body(12))
                    .foregroundStyle(.fgDim)
                Text("Enable")
                    .font(.body(12, weight: .semibold))
                    .underline()
                    .foregroundStyle(.clay)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Mode toggle button

private struct ModeButton: View {
    let label: String
    let system: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: system).font(.system(size: 12, weight: .regular))
                Text(label).font(.body(12, weight: .semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(active ? Color.clayInk : Color.muted)
            .background(Capsule().fill(active ? Color.clay : Color.clear))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat models

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, ai }
    let id = UUID()
    let role: Role
    /// Display text rendered in chat bubbles. For AI messages this is the
    /// short MSG line (or appQuestion answer), with the JSON results stripped
    /// so users see a clean conversational response.
    let text: String
    /// Full text to send back to Claude as conversation history. For AI
    /// messages, this carries the original raw response — including the JSON
    /// list it returned — so on the NEXT turn Claude can reference what it
    /// suggested before (avoid repeats on refresh, talk about specific
    /// recommendations, etc.). nil for user messages → fall back to `text`.
    let claudeText: String?

    init(role: Role, text: String, claudeText: String? = nil) {
        self.role = role
        self.text = text
        self.claudeText = claudeText
    }

    static let welcome = ChatMessage(
        role: .ai,
        text: "Tell me what you're looking for. I'll search every source and build a list."
    )
}

struct ChatBubble: View {
    enum Role { case user, ai }
    let role: Role
    let text: String

    var body: some View {
        HStack {
            if role == .user { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 4) {
                if role == .ai {
                    HStack(spacing: 6) {
                        Circle().fill(Color.moss).frame(width: 5, height: 5)
                        Text("NOMADAI")
                            .font(.mono(9, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(.muted)
                    }
                }
                Text(text)
                    .font(.body(14))
                    .foregroundStyle(role == .user ? Color.clayInk : Color.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: role == .ai ? 4 : 16,
                    bottomTrailingRadius: role == .user ? 4 : 16,
                    topTrailingRadius: 16,
                    style: .continuous
                )
                .fill(role == .user ? Color.clay : Color.surface)
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: role == .ai ? 4 : 16,
                    bottomTrailingRadius: role == .user ? 4 : 16,
                    topTrailingRadius: 16,
                    style: .continuous
                )
                .strokeBorder(role == .ai ? Color.line : Color.clear, lineWidth: 1)
            )
            if role == .ai { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Thinking dots

struct ThinkingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.moss)
                        .frame(width: 7, height: 7)
                        .opacity(phase == i ? 1.0 : 0.35)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16, bottomLeadingRadius: 4,
                    bottomTrailingRadius: 16, topTrailingRadius: 16,
                    style: .continuous
                )
                .fill(Color.surface)
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16, bottomLeadingRadius: 4,
                    bottomTrailingRadius: 16, topTrailingRadius: 16,
                    style: .continuous
                )
                .strokeBorder(Color.line, lineWidth: 1)
            )
            Spacer(minLength: 60)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { t in
                Task { @MainActor in phase = (phase + 1) % 3 }
            }
        }
    }
}

// MARK: - Suggestion chip

struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9))
                Text(text).font(.body(12, weight: .medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(.fgDim)
            .background(Capsule().fill(Color.bark))
            .overlay(Capsule().strokeBorder(Color.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI note callout

struct AINote: Equatable {
    enum Tone { case info, success, warning }
    let label: String
    let tone: Tone
}

struct AINoteView: View {
    let note: AINote

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(toneColor).frame(width: 6, height: 6)
            Text(note.label)
                .font(.mono(10, weight: .semibold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(.muted)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(toneColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(toneColor.opacity(0.35), lineWidth: 1))
    }

    private var toneColor: Color {
        switch note.tone {
        case .info: return .sky
        case .success: return .moss
        case .warning: return .sand
        }
    }
}

// MARK: - Filter section + chips

struct FilterSection<Content: View>: View {
    let label: String
    var note: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(label.uppercased())
                    .font(.mono(10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.muted)
                if let note {
                    Text(note)
                        .font(.mono(9, weight: .medium))
                        .tracking(1.0)
                        .foregroundStyle(.faint)
                }
            }
            content()
        }
    }
}

struct FilterChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.body(12, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(isOn ? Color.clayInk : Color.fgDim)
                .background(Capsule().fill(isOn ? Color.clay : Color.bark))
                .overlay(Capsule().strokeBorder(isOn ? Color.clay : Color.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct RadiusChip: View {
    let value: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(value) mi")
                .font(.body(12, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .foregroundStyle(isOn ? Color.clayInk : Color.fgDim)
                .background(Capsule().fill(isOn ? Color.clay : Color.bark))
                .overlay(Capsule().strokeBorder(isOn ? Color.clay : Color.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Error banner

struct ErrorBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.berry)
            Text(text)
                .font(.body(12, weight: .semibold))
                .foregroundStyle(.fg)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.berry.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.berry.opacity(0.35), lineWidth: 1))
    }
}

#Preview {
    SearchView().preferredColorScheme(.dark)
}
