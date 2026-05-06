# CLAUDE.md — NomadAI iOS

> **Auto-loaded by Claude Code at session start.** Read this top-to-bottom before doing anything else. This file orients you on the project, what's been built, the user's preferences, and what to build next.

---

## Quick orientation

- **Product:** NomadAI — an AI-powered campsite + overland route finder. Live web version at https://nomadai.us.
- **This project:** Native iOS rewrite in SwiftUI. The web app is being deprecated; iOS will replace it.
- **User:** Luke Browne ([@lukeb230](https://github.com/lukeb230) on GitHub, lukebrowneo20@gmail.com). Solo dev. Owns nomadai.us. Has Xcode 26.4 installed.
- **Backend:** Stays unchanged — same Vercel Functions in [`/api/*`](../api/) and same Supabase project serve both web and iOS.
- **Status:** All four tabs and the Settings modal are fully built and visually rendering on iPhone 17 Pro simulator. SwiftData persistence + first-launch seeding work end-to-end. Search → Claude proxy → SwiftData round-trip is wired and tested live. Ready for Phase 2 of the "make everything functional" roadmap.

---

## What you should read first

```
NomadAI IOS/
├── CLAUDE.md            ← you are here
├── README.md            ← Xcode setup walkthrough (fonts, Supabase SDK, Info.plist)
├── docs/
│   ├── README.md        ← reading order + open product decisions
│   ├── design-tokens.md ← colors, type, spacing — already in Swift form
│   ├── api-contract.md  ← every /api/* endpoint with shapes + rate limits
│   ├── state-model.md   ← cf_* localStorage keys → SwiftData @Models
│   ├── business-logic.md ← query classification, prompts, optimizer, sync
│   └── screen-inventory.md ← every screen + modal mapped to redesign HTML
├── reference/
│   ├── NomadAI Redesign.html ← canonical pixel-accurate design — open in browser
│   └── NomadAI-Design-Brief.md ← canonical product spec
└── NomadAI/
    ├── NomadAI.xcodeproj
    └── NomadAI/         ← all Swift sources (PBXFileSystemSynchronizedRootGroup)
        ├── App/         ← @main entry. Calls Seed.seedIfNeeded on root .task
        ├── Design/      ← Tokens.swift, Typography.swift
        ├── Models/      ← Campsite (+ DTO + upsert helper), Trip, TripStop,
        │                  CompletedTrip, Profile, MockData
        ├── Services/    ← Claude/Campsite/Places/Weather + NomadAIPersona,
        │                  RouteFetcher, RouteOptimizer, Seed, SearchResultsStore
        ├── Views/
        │   ├── ContentView.swift  (custom pill TabView root)
        │   ├── Tabs/    ← Home, Search, Map (CampsiteMapView), Saved
        │   ├── Modals/  ← SettingsSheet
        │   └── Components/ ← BrandMark, CampsiteCard, JournalEntry, QuickActionGrid,
        │                     StampTile, StatStrip, TripHeroCard
        ├── Assets.xcassets ← 24 token color sets + AppIcon + AccentColor
        └── Fonts/       ← drop Fraunces / Inter Tight / JetBrains Mono .ttf here
```

When in doubt, **read the canonical [`reference/NomadAI Redesign.html`](./reference/NomadAI Redesign.html) in a browser** side-by-side with [`docs/screen-inventory.md`](./docs/screen-inventory.md). The design HTML is the source of truth.

---

## Conversation history (what we've discussed)

### Session 1 — Design + scaffolding (prior)
Design handoff bundle from claude.ai/design unpacked into [`reference/`](./reference/). Web `app.html` redesign was full-ported on the `redesign` branch. Scenario B settled: **iOS replaces web; web becomes archive.** Don't fix web bugs. Don't treat `app.html` as Swift structure reference. Same Vercel + Supabase backend.

### Session 2 — Build out every tab + Settings + Phase 1 functional pass (this session)

**Tabs built:**
- **HomeView** — already populated with mock data when this session started. Then the trip hero map preview was upgraded from the fake SVG curve (`RoutePath`) to a real MapKit `Map` showing `MockTrip.sampleRouteStops` with a dashed clay polyline. Polyline now follows actual roads via `MKDirections` (see Architecture decisions).
- **SearchView** — full build: 2-segment Mode toggle, AI chat panel (chat scroll + suggestion rail + input bar with mic stub + send), Location panel (text input + Type filter chips + Radius chips). User-removed the Sources filter section ("just searches all sources every time"). Both modes wired to live services. AI uses `ClaudeService` → `/api/claude` proxy with `NomadAIPersona.systemPrompt` as Anthropic's top-level `system` field. Location uses `CampsiteService` → `/api/search-campsites`. Returned campsites are upserted into SwiftData (see Architecture decisions).
- **CampsiteMapView (Map tab)** — full build: 3-segment glass mode bar (Results / Saved / Route), custom teardrop pins via SF `mappin.circle`, numbered route pins (moss=done / clay=next / slate=future), `MapPolyline` for Route mode (also road-following), `MapPopupCard` bottom sheet on pin tap, "Search this area" pan-detection button (action stubbed). Mode change auto-recenters the map via `Self.region(for:)`. **Maps always render in dark mode** even when the app is in light mode (see Architecture decisions).
- **SavedView** — full build with all 3 modes + interactions: 
  - **Route**: dashed-spine timeline of `Trip.sortedStops`, numbered clay/moss dots, leg-distance labels with compass icon, header pills (Round trip / Start from me / Optimize), 4-cell metric strip (Total mi, Stops, Driving hr, Fees), action row (Map view / Share route / Start trip — last two are stubs). **Drag-to-reorder works** via `.draggable(stop.campsiteId)` on the row + `Color.clear`-overlaid `.dropDestination` zones between rows. Optimize button calls `NearestNeighbor.order(...)` and re-saves.
  - **All**: state-filter `Menu` + 3 sort chips (Date / A–Z / Distance), `LazyVStack` of `CampsiteCard`s. Save button on the card mutates `isSaved` via `@Environment(\.modelContext)` so saves persist.
  - **Passport**: leather-toned cover with parchment text + dashed inner border, `StatStrip` reading real `visited`/`completed` counts, 2-col `LazyVGrid` of `StampTile`s. `StampTile` has circle/rect variants, 6 color rotations (moss/clay/rust/slate/sand/berry), rotated `-6°` date cancel, locked-state diagonal-stripe pattern via Canvas.

**Settings modal:**
- New file [`Views/Modals/SettingsSheet.swift`](./NomadAI/NomadAI/Views/Modals/SettingsSheet.swift). Bottom sheet (`.presentationDetents([.large])`) opened from the Home gear button. Sections: Appearance / Search defaults / Notifications / Data / Account / About / version footer.
- **Wired:** Light mode toggle (writes `@AppStorage("color_scheme")`), default radius chips (writes `@AppStorage("default_radius")`), Clear saved spots / Clear passport / Reset all data (real SwiftData mutations, alert-confirmed), About links open in Safari, version reads from `Info.plist`.
- **Stubbed:** Trip reminders (opens iOS Settings.app), Sign in (NoticeAlert), Stats (NoticeAlert), Clear search history (greyed out — no real history yet).

**Bugs fixed this session:**
- Light/dark toggle was greyed out — `SettingsRow` was a `Button`, which made the trailing `Toggle` non-interactive. Refactored to `HStack + .contentShape + .onTapGesture`.
- Settings auto-presented on tab return — `@State showingSettings` lived inside private `Topbar`, lifecycle was unreliable. Lifted to `HomeView` + passed `@Binding` down + moved `.sheet` to outer ScrollView.
- Sheet kept old appearance after toggling theme — sheets present in their own context. Added `.preferredColorScheme(schemePref == "light" ? .light : .dark)` directly on the sheet body so it observes `@AppStorage` and re-renders live.
- Search results disappeared on tab switch — `@State` dies with the view. Lifted `results`/`messages`/`aiNote` into a process-wide [`SearchResultsStore`](./NomadAI/NomadAI/Services/SearchResultsStore.swift) `@Observable` singleton.

**Phase 1 (Validate AI search end-to-end + harden persona, parser, persistence) — shipped:**
- 🆕 [`Services/NomadAIPersona.swift`](./NomadAI/NomadAI/Services/NomadAIPersona.swift) — single `systemPrompt` constant (the voice/identity).
- ✏️ `ClaudeService.send` accepts optional `system: String?` and includes it in the request body. Proxy forwards verbatim to Anthropic.
- ✏️ `SearchView`'s three prompt builders no longer recite the persona; they only carry user-specific instructions + format spec.
- ✏️ `Models/Campsite.swift` — `Coordinates` decoder now accepts Double *or* numeric String (Claude occasionally returns lat/lng as strings). New `Campsite.upsert(from:into:)` static helper that updates discoverable fields while preserving `isSaved`/`isVisited`/`savedAt`/`rating`/`note`.
- ✏️ `SearchView` calls `Campsite.upsert` + `try? ctx.save()` after both AI and Location parsing. Saved tab's `@Query` picks them up automatically.
- ✏️ `parseClaudeResponse` uses backward search for `</planning>` (handles nested thinking blocks) and `print()`-logs decode failures with the raw slice for debugging.
- **Live verified via curl** against `https://nomadai.us/api/claude`: app-question persona honored ("I'm NomadAI, your AI guide…"), location mode returns valid `MSG: …` line + JSON array of plausible Moab BLM sites with real coordinates. JSON came back wrapped in ` ```json ` fences — handled by the existing first-`[` to last-`]` slice.

---

## What's actually built vs. stubbed (current state)

### Built and working

- **Design system** — Tokens, Typography, FrauncesEmphasis, all 24 color tokens. Light + dark variants automatic.
- **All four tabs** — Home, Search, Map, Saved. All visuals match the redesign. All interactions (where infrastructure exists) wired to real services or SwiftData.
- **SettingsSheet** — fully built and wired (see above).
- **SwiftData** — `Campsite`, `Trip`, `TripStop`, `CompletedTrip`, `Profile` schema active. First-launch seeding via [`Services/Seed.swift`](./NomadAI/NomadAI/Services/Seed.swift) puts real data in the DB so all tabs render populated immediately. Settings "Reset all data" wipes everything + clears the seed flag so it re-seeds next launch.
- **AI search pipeline** — `classifyQuery` → `appQuestion` / `location` / `route` → model + max_tokens selection → prompt builder → `ClaudeService.send` with `NomadAIPersona.systemPrompt` → `parseClaudeResponse` → `Campsite.upsert` → `ctx.save()` → SavedView `@Query` updates. Tested live.
- **Location search** — `CampsiteService` → `/api/search-campsites` with selectable Type tags + Radius chips. Results upsert to SwiftData.
- **Trip planning** — drag-to-reorder, `NearestNeighbor` optimize button, real metric strip (haversine totals).
- **Passport** — `StampTile` grid, real visited/state/trip counts, deterministic color/variant rotation.
- **Maps** — `MapKit` integration. Route polylines follow actual roads via `RouteFetcher` (parallel `MKDirections.calculate()` with process-wide cache). Maps always dark regardless of app theme.
- **Theme** — light/dark via `@AppStorage("color_scheme")` reads `preferredColorScheme` on `ContentView` and on `SettingsSheet` body. Sheet updates live.
- **Search results persistence** — `SearchResultsStore` keeps results/chat history/AI note across tab navigation.

### Stubbed / TODO (won't break anything; just no-ops or simplified)

- **CoreLocation** — `userLat: 38.5733, userLng: -109.5498` (Moab) is hardcoded across SearchView, MapView, SavedView, RouteOptimizer, RouteFetcher's "Start from me" use. No "Near me" buttons functional. Phase 3.
- **Map "Search this area"** — button appears on pan but tap is a stub (just dismisses the button). Phase 4.
- **MapView Results mode** — still reads from `MockCampsite.resultsSample` instead of `@Query` on the SwiftData Campsites. Phase 4.
- **CampsiteCard "Trip" action button** — empty closure. Should append to active `Trip` as a `TripStop`. Phase 2.
- **Saved Route action row** — "Map view" / "Share route" / "Start trip" all log TODO. Phase 6.
- **Trip completion / per-stop visited mutation** — not wired. Phase 6.
- **Photo loading** — all `CampsiteCard` photos, `MapPopupCard.thumb`, `StampTile`, `JournalEntry` thumbs are placeholder gray boxes. `PlacesService` exists but isn't called yet. Phase 5.
- **Default radius** — `@AppStorage("default_radius")` is *written* by Settings but *not read* by `SearchView` (still hardcoded to 50). Phase 2.
- **Search history persistence** — Settings has the row greyed out. No history is tracked yet.
- **Supabase / sign in / sync** — SDK not installed. "Sign in" is a NoticeAlert. Phase 7.
- **Trip reminders / notifications** — Settings row opens iOS Settings.app instead of `UNUserNotificationCenter`. Phase 8.
- **Stats modal** — Settings "Your stats" shows a NoticeAlert. Phase 9.
- **Voice input** — mic button on Search is a no-op. Phase 9.
- **Fonts** — Fraunces / Inter Tight / JetBrains Mono `.ttf` files not added. Text uses system fallbacks. Layout is correct; typography only when fonts are dropped in (see [`README.md` step 3](./README.md)).

---

## Architecture decisions (settled — don't re-litigate)

### Original
| Decision | Choice | Why |
|---|---|---|
| UI framework | **SwiftUI** | Modern, less boilerplate. |
| Persistence | **SwiftData** | Native, composes with `@Query`. |
| Map provider | **MapKit** | Free, native. Mapbox deferred to v2. |
| Tab bar | **Custom pill** | System TabView can't produce the floating-pill design. |
| Claude API | **Through `/api/claude` proxy**, not Anthropic SDK directly | The Vercel Function holds `ANTHROPIC_KEY`; iOS doesn't ship the key. Rate-limited 10/IP/hr. |
| Auth | **Sign in with Apple primary, Supabase email/password fallback** | App Store requires SIWA if any other auth is offered. |
| Color tokens | **Asset catalog with auto-generated symbols** | Xcode 16+ auto-emits `Color.bg` etc. |
| Project structure | **`PBXFileSystemSynchronizedRootGroup`** | Files in `NomadAI/NomadAI/` auto-included. Don't edit `.pbxproj`. |
| Sync | **Last-write-wins via Supabase `updated_at`** | Matches web. |
| Photo source | **`/api/places`** (Google Places via proxy) | Same as web. |
| Voice search | **`SFSpeechRecognizer`** | Native. Needs Info.plist usage descriptions. |

### Added this session
| Decision | Choice | Why |
|---|---|---|
| Anthropic system framing | **Top-level `system` field**, not embedded in user message | Cleaner separation; the proxy at [`api/claude.js`](../api/claude.js) is a pure pass-through and forwards `system` straight through. |
| NomadAI persona location | **Single `NomadAIPersona.systemPrompt` constant** in [`Services/NomadAIPersona.swift`](./NomadAI/NomadAI/Services/NomadAIPersona.swift) | One source of truth for the voice. All three prompt builders inject it via `ClaudeService.send(system:)`. |
| Cross-tab Search state | **Process-wide `@Observable` singleton** in [`Services/SearchResultsStore.swift`](./NomadAI/NomadAI/Services/SearchResultsStore.swift) | `@State` dies on tab dismount; users hated losing results when navigating away. |
| Maps in light-mode app | **Always render in dark mode** via `.environment(\.colorScheme, .dark)` on the `Map` view | Dark Apple Maps tiles match the brand mood; light tiles clash with the canyon-clay accents. Applied on `TripHeroCard` map and `CampsiteMapView` map. |
| Road-following routes | **`MKDirections` fan-out via `TaskGroup`**, stitched + cached, in [`Services/RouteFetcher.swift`](./NomadAI/NomadAI/Services/RouteFetcher.swift) | Straight-line polylines look fake. `MKDirections.driving` per consecutive pair, parallel via TaskGroup, cached process-wide by rounded coord string. Used by both Home hero and Map Route mode. |
| Campsite ID strategy | **Synthesized `name + city + state`** + `upsert(from:into:)` helper that preserves user state | DTO has no stable id from upstream; collisions are real (same site searched twice). Upsert updates discoverable fields but never overwrites `isSaved`/`isVisited`/`savedAt`/`rating`/`note`. |
| Coordinate decoding | **Tolerant `Coordinates` decoder** that accepts Double or numeric String | Claude occasionally emits `"lat": "39.0"` (string). Fail-soft on this is worth the 6 lines. |
| First-launch data | **Versioned seed via `nomad_did_seed_v1` UserDefault** | Lets the user open the app and see populated tabs without having to use Search first. Settings "Reset all data" clears the key so seeding re-runs. |
| Drag-reorder in non-List | **`.draggable(stop.campsiteId)` + `Color.clear`-overlaid `.dropDestination` zones** between rows | Preserves the dashed-spine aesthetic that a `List` would break. |
| Settings sheet color scheme | **`.preferredColorScheme(...)` applied directly on the sheet body** | Sheets present in their own context — App-level `preferredColorScheme` doesn't reactively flow into already-presented sheets. |

---

## What you need to do next — Phase 2-9 roadmap

Phase 1 (validate AI search + harden persona/parser/persistence) is shipped. Remaining roadmap from the prior planning convo, in dependency order:

### Phase 2 — Connect Settings → Search → Saved (small)
- `SearchView` reads `@AppStorage("default_radius")` as initial `selectedRadius`.
- `CampsiteCard`'s "Trip" action (empty closure today, [`CampsiteCard.swift`](./NomadAI/NomadAI/Views/Components/CampsiteCard.swift)) appends the campsite to the active `Trip` as a new `TripStop`. If no active trip exists, create one.

### Phase 3 — CoreLocation
- Add `NSLocationWhenInUseUsageDescription` to Info.plist.
- New `LocationService` (CLLocationManager wrapper, async API).
- Wire "Near me" buttons in Search location mode + Map's "Search this area".
- Replace hardcoded Moab fallbacks across SearchView, MapView, SavedView's distance sort, RouteOptimizer.
- Graceful fallback to Moab when permission denied.

### Phase 4 — Map ↔ everywhere data flow
- Map "Results" mode reads from `SearchResultsStore.shared.results` (or `@Query` for `Campsite.fromDatabase == true`) instead of `MockCampsite.resultsSample`.
- "Search this area" button calls `CampsiteService.search(lat:lng:radius:)` at panned center, upserts results.
- "Map view" button on Saved Route mode switches to Map tab + Route mode.
- Tap a pin's popup "Open" pushes a new `CampsiteDetailView`.

### Phase 5 — Photo loading
- `AsyncImage` driven by `PlacesService.searchPhotoReferences(...)` → `photoURL(...)`.
- Apply to `CampsiteCard`, `MapPopupCard.thumb`, `StampTile`, `JournalEntry`.
- Cache via `URLCache` (already declared in `PlacesService`).
- Skeleton + Wikimedia fallback in v2.

### Phase 6 — Trip lifecycle
- "Start trip" switches to Map tab Route mode + sets `currentStopIndex = 0`.
- Per-stop "Mark visited" mutates `Campsite.isVisited = true`, advances `currentStopIndex`.
- "Complete trip" creates `CompletedTrip`, sets `Trip.completedAt`. Stamps appear in Passport automatically.
- HomeView's `TripHeroCard` reads the real active `Trip` instead of `MockTrip.sample`.

### Phase 7 — Supabase auth + sync
- Add Supabase Swift SDK via SPM (`https://github.com/supabase-community/supabase-swift`).
- `SupabaseService` wrapper using URL + anon key from web's `app.html`.
- Sign in with Apple primary + email/password fallback.
- Pull on foreground, debounced push on local mutation. Last-write-wins.

### Phase 8 — Notifications
- `UNUserNotificationCenter` permission flow.
- Schedule per-stop reminders based on `TripStop.scheduledDate`.
- Wire the Settings "Trip reminders" row to ask permission inline.

### Phase 9 — Polish
- Voice input via `SFSpeechRecognizer` on the mic button.
- Stats modal (the Settings "Your stats" target).
- "Share route" via `ShareLink` with the trip's Supabase share URL.
- Empty-state copy refinement, accessibility audit, light-mode visual polish.

---

## What features the app has (the product, not the code)

Pulled from the design brief; full detail in [`reference/NomadAI-Design-Brief.md`](./reference/NomadAI-Design-Brief.md).

### Core value prop
"Stop researching. Start exploring." — natural-language campsite search aggregating Recreation.gov, iOverlander, The Dyrt, BLM/Dispersed, Campendium. Builds multi-stop overland trips from a single sentence and pins them on a live map.

### Three audiences: Overlanders · Campers · Beginners

### Tabs
| Tab | Purpose |
|---|---|
| **Home** | Editorial dashboard — current trip (real MapKit + road-following polyline), stats, camp journal |
| **Search** | AI chat OR location-mode chip-filter search. Both wired. Results persist via SearchResultsStore. |
| **Map** | MapKit with mode toggle: Results / Saved / Route. Custom pins, popup, polyline, pan-to-search button (action stubbed). |
| **Saved** | All saved (filter+sort) / Route timeline (drag-reorder, optimize) / Passport stamp grid. |

### Modals
**Built:** Settings.
**TODO:** Stats · Profile · Auth · Trips history · Photo lightbox · Campsite detail.

### Backend services and data flow

```
                   ┌─────────────┐
   iOS / web ─────▶│ /api/claude │────▶ Anthropic Messages API (rate-limited 10/IP/hr)
                   └─────────────┘     ↑ NomadAIPersona.systemPrompt sent as `system` field
                   ┌──────────────────────┐
   iOS / web ─────▶│ /api/search-campsites │──▶ Supabase `campsites` table (verified data)
                   └──────────────────────┘
                   ┌─────────────┐
   iOS / web ─────▶│ /api/places │────▶ Google Places API (photo proxy) — not yet called from iOS
                   └─────────────┘
                   ┌─────────────────────────┐
   Sundays 03:00 ─▶│ /api/refresh-campsites  │──▶ Recreation.gov RIDB / OSM Overpass / USFS
                   └─────────────────────────┘
                   ┌──────────┐
   iOS / web ─────▶│ Supabase │ (auth + sync — not wired from iOS yet)
                   └──────────┘
                   ┌────────────┐
   iOS / web ─────▶│ Open-Meteo │ (direct, no proxy needed) — not yet called from iOS
                   └────────────┘
```

Full endpoint contract in [`docs/api-contract.md`](./docs/api-contract.md).

---

## Design system at a glance

Full spec in [`docs/design-tokens.md`](./docs/design-tokens.md).

- **Mood:** Earthy high-tech. Deep forest at night meets canyon clay sunset, parchment in light mode.
- **Type:** Fraunces (display) + Inter Tight (UI) + JetBrains Mono (10–11px micro-labels uppercase tracked .12–.18em).
- **Color anchor:** `clay` (`#c4825e` dark, `#9c5b3a` light) is the primary CTA / accent / italic-emphasis color. `clayInk` is the text-on-clay color.
- **Shape language:** Softer radii (14–20pt), 1px hairlines, dotted/dashed dividers evoking topo or paper folds, pill-style chips and CTAs (radius 999).
- **Iconography:** Custom 1.5px stroke line SVGs, rounded caps. SF Symbols substitute for ~80%.
- **Themes:** Dark default, light parchment alternative. **Maps stay dark in both.** Toggled via `@AppStorage("color_scheme")` + `.preferredColorScheme(...)` on `ContentView` and on every sheet body.

---

## Patterns from web that DON'T transfer (don't copy these)

- **`cardHTML()` legacy structure** — use the redesign's `.site-card` markup (already what `CampsiteCard.swift` is based on). Don't port emoji.
- **`localStorage` `cf_*` keys** — use SwiftData (see [`docs/state-model.md`](./docs/state-model.md)).
- **`#app.light` class toggle** — use SwiftUI's `colorScheme` modifier or asset auto-theming.
- **`setTimeout` / `setInterval`** — use Swift Concurrency.
- **Desktop sidebar layout** at `@media (min-width: 768px)` — iOS is mobile-first.
- **PWA install banner** — irrelevant for native app.
- **Manual ID strings** — use `@Identifiable` / `id:`.
- **JS-style hex colors `#e8d5b7`** in inline styles — use `Color.bg`, `Color.clay`, etc.
- **Emoji icons** in chrome — use SF Symbols. Emoji can stay in user-authored content (notes, journal entries).

---

## Communication preferences (Luke specifically)

These are observed across both sessions:

1. **Confirm before risky operations.** Pushing to main, force-pushing, dropping data, modifying infra — always ask first.
2. **Plan before doing.** For non-trivial work, present a phased plan (with options if appropriate) before writing code. Use plan mode + the plan file for multi-step features.
3. **Ask scoping questions early.** Two or three crisp options ("how far should this pass go?") works well. He picks fast and trusts you to execute.
4. **Direct, action-oriented when ready.** Once a plan is approved, just execute. Don't keep re-asking.
5. **Cite file paths with markdown links** like [`SearchView.swift`](./NomadAI/NomadAI/Views/Tabs/SearchView.swift) — he clicks through to verify.
6. **Audit / verify the result, don't just ship.** Build, install, launch, and where possible exercise the path. Report findings honestly. Use TODO comments liberally in stub code.
7. **Don't fix things outside the scope of the current task** unless explicitly authorized.
8. **Don't read simulator screenshots into chat.** iPhone 17 Pro shots are 1206×2622, exceed the API's 2000px many-image limit, and trigger a "dimension limit" warning at the end of every assistant reply for the rest of the session. Build, install, launch — but stop at "app is running"; let Luke inspect the simulator himself. (Saved as `feedback_no_screenshots` memory; survives session resets.)
9. **End-of-turn summary should be tight** — what changed, what's next. One or two sentences usually.

---

## Open product decisions (some answered)

1. ~~**Sign in with Apple vs email/password.**~~ Settled: support both. SIWA primary. Email/password fallback. Phase 7 wires it.
2. ~~**MapKit vs Mapbox.**~~ Settled: MapKit for v1.
3. **Photo source priority.** Recommend keep `/api/places` (Google) primary. Wikimedia + Mapbox satellite fallbacks deferred.
4. **Web app deprecation date.** Still TBD. iOS launch should determine when web is sunset.
5. **Trip reminders.** Settings has the row but currently opens iOS Settings.app. Phase 8 wires `UNUserNotificationCenter`.
6. **Anthropic key model.** Settled: server-side via `/api/claude` proxy. **Never embed `ANTHROPIC_KEY` in the iOS binary** — it can be extracted. The proxy holds it in Vercel env vars; iOS sends model + max_tokens + system + messages and the proxy forwards verbatim.

---

## Monetization plan (decided 2026-04-26 — not yet implemented)

**Two tiers: free + Pro at $4.99/mo or $39.99/yr.**

| Tier | Claude calls | Sync | Other |
|---|---|---|---|
| **Free** | 5 / hour | None (local SwiftData only) | All UI/features unlocked |
| **Pro** ($4.99/mo or $39.99/yr) | 30 / hour | Full Supabase pull + push (multi-device) | Share-route, future Pro flags |

**Apple Small Business Program** — enroll for **15% cut** (qualifies while <$1M/yr; stays at 15% indefinitely under that threshold). At $4.99 sticker, net to Luke is ~$4.24/mo.

**Cost basis (April 2026):**
- Blended cost ~$1.55/user/mo today (10/hr global cap, ~70% light / 25% moderate / 5% active mix)
- Mostly Anthropic (Claude Haiku for app/location queries, Sonnet for routes); Google Places second; Apple MapKit free; Supabase + Vercel free tier covers tens of thousands of users
- Google's $200/month free Places credit zeroes out Places costs for the first ~5000 active users

**Margin math (gross margin = `revenue − cost / revenue`):**
- Pro at $4.99 sticker → $4.24 net → minus ~$1.55 free-tier-cost-equivalent (Pro users will use more) → ~$2.50–3.00 cost → **~$1.25–1.75 profit, ~30–40% gross margin** at typical Pro usage
- To hit 50% margin firmly, $5.99 sticker is more honest. $4.99 wins on price-point optics; $5.99 wins on unit economics. **Decide based on conversion sensitivity vs. margin floor.**

**Comparable apps in the category** (for pricing reference): The Dyrt Pro $35.99/yr, Campendium Pro $29.99/yr, AllTrails+ $35.99/yr, OnX Off Road $35.99/yr, iOverlander free with donations. Market clusters at $3–4/mo or $30–60/yr. NomadAI's AI search justifies the upper end.

**Funnel intent:**
- Free users see "AI paused — upgrade to Pro for higher limits" after their 5/hour cap hits → that's the conversion moment
- Free is single-device — visible "Sign in for Pro to sync across devices" friction creates a second conversion path
- Free tier still offers full saved-spots, full Map, full Trip planning — generous enough to be useful, not so generous that no one upgrades

**Implementation TODO (when ready to ship):**
1. **`api/claude.js` rate limiter by tier** — read user JWT from Supabase, look up tier (free vs pro) from a `user_subscriptions` Supabase table, apply 5/hr or 30/hr limit. Anonymous (no JWT) defaults to free.
2. **App Store Connect** — register subscription products, configure auto-renewable subscription group with monthly + annual SKUs.
3. **StoreKit 2 integration in iOS** — `Product.products(for:)` to fetch SKUs, `product.purchase()`, `Transaction.currentEntitlements` to check Pro status. New `SubscriptionService` singleton mirroring `AuthState`.
4. **Settings → "Manage subscription"** row when Pro; **"Upgrade to Pro"** call-to-action when free.
5. **Sync gate** — `SyncService.start()` becomes a no-op if `!SubscriptionService.shared.isPro`.
6. **Receipt validation** — server-side via App Store Server Notifications v2; cache entitlement in `user_subscriptions` table for /api/claude rate limiter to read.
7. **Apple Small Business Program enrollment** in App Store Connect (one-click; lowers commission to 15% from day one).

**Honest caveats (re-read before launch):**
- Outdoor/utility app conversion is brutal — 1–3% free→paid is realistic. To clear $5K/mo profit: ~50K free users → ~1500 paid.
- Heavy "cap-saturating" users (~1% of base) dominate cost; Pro tier's 30/hr cap is the lever — set it tighter if abuse becomes real.
- Server-side abuse (rotating-IP bots) is unrelated to per-user pricing; defend with a Vercel-edge IP rate limiter as a separate concern.

---

## Useful commands

From `NomadAI IOS/NomadAI/`:

```bash
# Build
xcodebuild -project NomadAI.xcodeproj -scheme NomadAI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build

# Install + launch
APP_PATH=$(find /Users/lukebrowne/Library/Developer/Xcode/DerivedData/NomadAI-* \
  -name "NomadAI.app" -path "*Build/Products/Debug-iphonesimulator/*" \
  -not -path "*Index.noindex*" | head -1)
xcrun simctl install booted "$APP_PATH"
xcrun simctl launch booted LukeBrowne.NomadAI

# Logs (use this instead of screenshots for state inspection)
xcrun simctl spawn booted log show --last 2m --predicate 'process == "NomadAI"' | tail -50

# Toggle theme via UserDefaults (avoids navigating to Settings while testing)
xcrun simctl spawn booted defaults write LukeBrowne.NomadAI color_scheme light  # or dark

# Wipe SwiftData + reset seed (uninstall is the simplest way)
xcrun simctl uninstall booted LukeBrowne.NomadAI

# Live-test the Claude proxy (verifies persona + JSON format without rebuilding)
curl -sSL -X POST https://nomadai.us/api/claude \
  -H 'Content-Type: application/json' \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":500,
       "system":"You are NomadAI...","messages":[{"role":"user","content":"..."}]}'

# Stop
xcrun simctl terminate booted LukeBrowne.NomadAI
```

Bundle ID is `LukeBrowne.NomadAI`.

---

## When in doubt

1. Read [`docs/screen-inventory.md`](./docs/screen-inventory.md) for what to build
2. Read [`docs/design-tokens.md`](./docs/design-tokens.md) for how it should look
3. Read [`docs/api-contract.md`](./docs/api-contract.md) for what data shape to expect
4. Read [`docs/business-logic.md`](./docs/business-logic.md) for non-UI logic
5. Open [`reference/NomadAI Redesign.html`](./reference/NomadAI Redesign.html) in a browser for the canonical visual spec

If you're about to suggest something that contradicts a "decided" item in this file, pause and re-read the relevant section first.
