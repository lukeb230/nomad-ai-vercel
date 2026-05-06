# Screen Inventory

Every screen + modal in NomadAI, mapped to its location in the canonical [`NomadAI Redesign.html`](../reference/NomadAI Redesign.html) and to a target SwiftUI view.

Open the redesign HTML in a browser side-by-side with this doc when implementing each screen.

## Tab structure

The app has a fixed-bottom pill-style nav with 4 tabs. iOS uses `TabView` with a custom-styled tab bar (the system `TabView` doesn't easily produce the floating-pill design — implement a custom tab bar inside a `ZStack`).

| Tab | Order | SF Symbol | Swift view |
|---|---|---|---|
| Home | 1 | `house` | `HomeView` |
| Search | 2 | `magnifyingglass` | `SearchView` |
| Map | 3 | `map` | `MapView` |
| Saved | 4 | `bookmark` | `SavedView` |

---

## 1. Home — `HomeView.swift`

**Redesign reference:** lines 1393–1592 of `NomadAI Redesign.html`

Sections top-to-bottom:

| Section | Component |
|---|---|
| Topbar | `BrandMark` (Fraunces "Nomad*AI*") + "FIELD JOURNAL" mono subtitle + Settings & Profile icon buttons |
| Editorial hero | Eyebrow with pulse dot ("DAY 3 · ROLLING" or "WELCOME BACK") + Fraunces display headline with italic clay emphasis + muted subline |
| Trip hero card | `TripHeroCard` — SVG/Canvas map preview with route + EN ROUTE pill + stop chip rail + dashed progress bar + Directions/Next-stop/Route action row |
| Stat strip | 3-up grid: Visited / Trips / States. Tap → opens Stats or Trips History modal |
| Section header | "Field notes" mono eyebrow + "Camp journal" Fraunces title + "All entries →" CTA |
| Camp journal | List of `JournalEntry` rows: 68px thumb + name + meta + 5 stars + days-ago aside |
| Section header | "Shortcuts" + "Before you air down" |
| Quick-action grid | Magazine-style 1+2 grid: featured tile (Ask AI) + 2 small (Map, Plan a route) |

**Empty states:**
- No active trip → `TripHeroEmpty` with map icon + headline + CTA
- No journal entries → "Mark campsites as visited to start your journal."

---

## 2. Search — `SearchView.swift`

**Redesign reference:** lines 1595–1736

| Section | Component |
|---|---|
| Topbar | "SEARCH" mono eyebrow + "Find your *spot*" Fraunces title + history icon |
| Search hero | Mono "★ Ask freely" eyebrow + "Tell it where to, and *it'll read the land*" Fraunces with italic + muted sub |
| Mode toggle | Pill with two segments: ✦ Ask AI / 📍 Location |
| **AI mode panel** | `ChatCanvas` with topo background + scrollable messages + suggestion rail + `ChatInputBar` (textarea + mic + clay send button) |
| **Location mode panel** | `LocationSearchBar` (text input + clear) + Filter chips section + Source chips section + Search radius radio row + "Search the field" big clay CTA |
| AI note | Small callout below chat: "Route query · 7 stops · cached 18 min ago" or "⚡ Showing cached results" |
| Results | `CampsiteCardStack` |

### Sub-components

- `ChatMessage(role: .user | .ai)` — bubble with clay (user) or surface (ai) bg
- `ChatThinking` — three pulsing dots while waiting for Claude
- `SuggestionChip` — clickable suggestion pill in the chat-canvas rail
- `FilterChip(state: .off | .on, label, color)` — used for type/source/radius
- `RadiusRow` — 4 pills: 25 / 50 / 100 / 200 mi

---

## 3. Map — `MapView.swift`

**Redesign reference:** lines 1739–1808

| Section | Component |
|---|---|
| Topbar | "MAP" mono eyebrow + "The *field*" Fraunces title + location icon button |
| Map container | `MapKit` Map view, full-bleed inside rounded card |
| Mode bar | Floating glass-blur pill at top: Results / Saved / Route segments |
| Pins | Custom teardrop+dot annotations colored by source (clay for active, moss for done, slate for outline) |
| Route line | `MKPolyline` connecting trip stops in order, dashed clay |
| Floating CTAs | "Search this area" clay pill (appears on pan) + small mono "Tap map to search that area" hint above |
| Selected popup | `MapPopupCard` — bark surface card at bottom: thumb + name + meta + "Open" clay button |
| Below map | Section header "Route · active" + active route info card |

### Sub-components

- `MapPinView(source: Source, isActive: Bool)` — custom `Annotation` content
- `MapModeBar(selected: MapMode)` — `Map.Result` / `.Saved` / `.Route`
- `MapPopupCard(campsite:)` — slides up when a pin is tapped

---

## 4. Saved — `SavedView.swift`

**Redesign reference:** lines 1811–1931

| Section | Component |
|---|---|
| Topbar | "SAVED" + "Your *pins*" + share icon |
| Saved head | "The *long way* — your draft" Fraunces title + sub |
| Mode tabs | Underline-clay tabs: Route / All saved · N / Passport |
| **Route mode** | `TimelineRoutePlanner` |
| **All saved mode** | `SavedListFilterBar` (state dropdown + sort chips) + `CampsiteCardStack` |
| **Passport mode** | `PassportCover` + `StampGrid` |

### Timeline route planner sub-components

| Component | What it shows |
|---|---|
| `TimelineHeader` | "Round trip" + "Start from me" toggle pills + "Optimize" clay CTA |
| `TripMetaRow` | Total miles / Stops / Driving hours / Fees, in Fraunces numerals |
| `TimelineList` | Vertical dashed-spine container |
| `TimelineStop` | Numbered clay dot + `TripStopCard` (thumb + name + sub + drag handle) |
| `TimelineLeg` | Distance/time row between stops, mono caption with compass icon |
| `TimelineActions` | 2-up grid: Map view / Share route / **Start trip** (clay primary, full-width) |

### Passport sub-components

| Component | What it shows |
|---|---|
| `PassportCover` | Leather-tan card with topo overlay + dashed inner border + "NomadAI · Field Passport" mono label + "Book No. 01" Fraunces title + "24 stamps · 11 states · 7 trips" count |
| `StampGrid` | 2-column grid of `Stamp` tiles |
| `Stamp(variant: .circle | .rect, color, locked)` | Square/circle aspect 1:1, color-tinted dashed inner border, icon + serial number top, name + location, rotated date cancel bottom-right |
| `StampLocked` | Diagonal-stripe background pattern, faint colors |

---

## Modals

iOS approach: use `.sheet(isPresented:)` for slide-ups and `.fullScreenCover` for full-screen. `.presentationDetents([.medium, .large])` for the bottom sheets that need to be partial-height.

### Settings — `SettingsModal.swift`
**Redesign:** general sheet pattern. Sections: Appearance / Search defaults / Notifications / Data / Account / About + version footer. **Bottom sheet, `[.large]` detent.**

### Stats — `StatsModal.swift`
**Redesign:** redesign HTML doesn't have a bespoke section; use the original web pattern (grid of stat cards) styled with new tokens. Bottom sheet, `[.medium, .large]` detents.

### Profile — `ProfileModal.swift`
Centered card. Avatar (tappable) + email + name input + clay Save + sign-out link. Use `.sheet(presentationDetents: [.medium])`.

### Trips History — `TripsHistoryModal.swift`
Bottom sheet, list of `CompletedTripCard` rows.

### Auth — `AuthModal.swift`
Centered card. **For iOS, prefer Sign in with Apple as the primary path** (AppKit-style button), with Supabase email/password as the fallback "Or sign in with email" option. The redesign auth modal (lines 891–903) is a useful style reference but the structure should be different on iOS.

### Photo Lightbox — `PhotoLightbox.swift`
Full-screen black backdrop. Swipe left/right between photos. Pinch-to-zoom (use `.gesture(MagnificationGesture())`). Close button top-right.

### Card Modal (full detail) — `CampsiteDetailView.swift`
Full-screen sheet showing one card expanded with all data: full carousel, weather, sun, description, tags, all action buttons, and the notes textarea. iOS typically does this as a `NavigationStack` push instead of a modal — recommend that.

---

## Cross-cutting components

These appear in multiple places:

### `CampsiteCard` — the atom
**Redesign:** `.site-card`, lines 720–940. Used in: Search results, Saved list, Home journal preview, Map popup (compact variant).

```swift
struct CampsiteCard: View {
  let campsite: Campsite
  var variant: Variant = .full   // .full | .compact | .savedActions

  // 16:9 photo carousel up top
  // Source badge top-left, fee badge top-right
  // Card body: name (Fraunces), location, distance
  // Field pills row
  // Description
  // Expandable section: 2x2 data cells (weather/wind/sunrise/sunset) + tag chips + action footer
  // Toggle button at bottom: "Show field data ▼"
}

extension CampsiteCard {
  enum Variant { case full, compact, savedActions, mapPopup }
}
```

### `BrandMark`
"Nomad*AI*" with the italic clay AI emphasis. Used in topbar.

### `IconButton`
38px circular icon button with hairline border. Used for Settings, Profile, Share, etc.

### `TopoBackground`
Concentric SVG circles overlay used as a texture on cards and the desktop backdrop.

### `ActionButton(style: .primary | .outline | .destructive)`
Clay primary, surface outline, berry destructive variants.

---

## Navigation map

```
TabView (custom pill-styled)
├── HomeView
│   ├─→ SettingsModal (sheet)
│   ├─→ ProfileModal (sheet)
│   ├─→ AuthModal (sheet, if not signed in)
│   ├─→ StatsModal (sheet, on stat strip tap)
│   ├─→ TripsHistoryModal (sheet, on Trips stat tap)
│   └─→ CampsiteDetailView (push, on journal entry tap)
├── SearchView
│   ├─→ CampsiteDetailView (push, on result card tap)
│   └─→ PhotoLightbox (fullscreen, on result card photo tap)
├── MapView
│   ├─→ CampsiteDetailView (push, on popup "Open" tap)
│   └─→ PhotoLightbox (fullscreen, from detail view)
└── SavedView
    ├─→ CampsiteDetailView (push, on saved card tap)
    ├─→ MapView (programmatic tab switch, on "Map view" CTA)
    └─→ Mode tabs internal (Route / All saved / Passport — segmented pickers)
```

## Implementation order recommendation

Build in this order to validate the design system early and unblock iteration:

1. **Tokens + Typography + custom TabView shell** — static visual proof
2. **CampsiteCard** (full variant only) — the atom shows up everywhere
3. **HomeView** with mock data — the most visually distinct screen
4. **SearchView** location mode (skip AI mode initially) → wire to `/api/search-campsites`
5. **SavedView** Route mode + timeline → SwiftData models live here
6. **MapView** with MapKit + custom annotations
7. **SearchView** AI mode → wire to `/api/claude`
8. **PassportCover + StampGrid** — visual showcase
9. **Modals** (Settings, Profile, Auth, Stats, Trips)
10. **Sync layer** (Supabase reads/writes + auth)
11. **Voice search**, photo lightbox, optimizations

Don't try to build everything in one go — get HomeView pixel-perfect first, then the rest will fall into place because the design system is locked in.
