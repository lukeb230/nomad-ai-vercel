# NomadAI — Design Brief for Redesign

A complete rundown of the NomadAI product, intended to be pasted into Claude (or any AI design tool) as context for generating a new visual direction. It covers what the app *does*, who it serves, the full screen inventory, the current look-and-feel, and the constraints any redesign needs to respect.

---

## 1. Product at a Glance

**Name:** NomadAI
**URL:** https://nomadai.us
**Tagline:** "Stop researching. Start exploring."
**One-liner:** An AI-powered campsite and overland route finder that searches every major camping data source at once, builds multi-stop trip routes, and optimizes the order — automatically.

**What makes it different:**
- Natural-language search powered by Claude ("Dispersed BLM sites along US-50 Nevada, 4x4 accessible, no fee")
- Aggregates across Recreation.gov, iOverlander, The Dyrt, BLM/Dispersed, and Campendium in a single search
- Turns a single query into a full multi-stop road trip — pinned on a live map, reorderable, auto-optimizable
- Lives weather, sunrise/sunset, fees, and directions on every result
- A "camp passport" that logs visited sites, states, and completed trips automatically
- Installable as a PWA; works fully mobile

**Primary audiences:**
1. **Overlanders** — building multi-day 4x4 corridors, need dispersed BLM intel
2. **Campers** — looking for anything from full-hookup RV to free no-fee sites
3. **Beginners** — don't know the difference between BLM and dispersed; want plain-English guidance

---

## 2. Tech Stack & Architecture

- Vanilla HTML/CSS/JS single-page app (no framework). The entire app lives in **app.html** (~4,300 lines).
- Hosted on **Vercel**. Serverless functions under `/api/`:
  - `claude.js` — proxy to Anthropic's Claude API (rate-limited 10/hr per IP)
  - `places.js` — Google Places proxy (photos, autocomplete)
  - `search-campsites.js`, `import-osm.js`, `import-recgov.js`, `import-usfs.js`, `refresh-campsites.js`, `setup-campsites.js` — DB sync and search for the Supabase campsite table
- **Supabase** for auth + syncing saved spots, passport stamps, and trip history across devices
- **Leaflet** for the map
- **localStorage** for everything when signed-out (saved spots, trip, visited, search history, light mode, ratings, journal notes)
- PWA: manifest + service worker (`sw.js`), installable to home screen
- Landing page at `index.html`, shared-spot page at `spot.html`

---

## 3. Screen Inventory

The app is mobile-first, capped to a 480px column centered on desktop. Four main tabs via a fixed bottom nav, plus a stack of modals and slide-up panels.

### 3.1 Landing Page (`index.html`)
Standalone marketing page, not part of the app shell. Includes:
- Fixed top nav with logo and "Open the app →" CTA
- Hero with a nature photo background, fade-up headline *"Stop researching. Start exploring."*, subhead, two CTAs, and a "demo box" showing a sample query
- Beginner bar ("New to camping or overlanding? Just ask NomadAI in plain English…")
- Source pills strip: Recreation.gov · iOverlander · The Dyrt · BLM / Dispersed · Campendium
- "Built for" use-case cards: Overlanding, Camping, Beginners
- "Route Intelligence" band with four feature tiles: Auto route planning, Smart optimization, Live conditions per site, Trip history & passport
- Final CTA + footer

### 3.2 App Shell (`app.html`)
Inside the app, four tabs toggle via the bottom nav:

1. **Home** — dashboard
2. **Search** — search + AI chat
3. **Map** — Leaflet map with mode toggle
4. **Saved** — bookmarks + route planner

Global elements that overlay the tabs:
- Fixed bottom nav (Home / Search / Map / Saved)
- Top bar per tab (title + subtitle + refresh/settings/profile buttons)
- "Back to top" button (floating, bottom-right)
- Install banner / iOS home-screen hint
- Offline banner
- Stats modal (slide-up)
- Settings modal (slide-up)
- Profile modal (centered)
- Passport modal (slide-up)
- Trips history panel (slide-up)
- Auth modal (centered)
- Photo lightbox (full-screen)
- Card modal (full-screen detail view for a single spot)
- Map "search this area" floating button and tap hint

---

## 4. Feature Detail by Tab

### 4.1 Home tab
A dashboard that opens on launch. Sections top-to-bottom:
- **Top bar:** "NomadAI 🏕️" title + "Your adventure dashboard" subtitle. Settings gear + user badge (Sign in / avatar).
- **Install banner** (dismissible) for PWA; iOS gets a "tap Share → Add to Home Screen" hint.
- **Current trip dashboard** — progress card showing the active planned trip: number of stops, next stop name, percent complete, quick-jump into the route.
- **Stats strip** — three tappable stat cards: Visited, Trips, States. Tap opens the Stats modal or Trips history.
- **Camp journal** — list of the user's own notes and ratings attached to visited spots.

### 4.2 Search tab
The heart of the product. Two search modes with a pill toggle at the top:

**✨ Ask AI (default)**
- Bordered chat container (480px tall) with a scrolling message thread, user bubbles right, AI bubbles left.
- Contenteditable input at the bottom with placeholder "Ask about campsites…", plus a voice-search mic button (hidden by default) and "✨ Ask AI" send button.
- Results render below the chat box as campsite cards.
- AI knows whether the query is an app-question, a route query ("along US-50 from Denver to Moab"), or a location query, and behaves differently. Route queries return an ordered list of stops with strict geographic distribution rules ("middle-biased, no clustering near endpoints, strict ordering").
- Cached queries return instantly with an "⚡ Showing cached results" note.
- Rate-limited to 10 AI calls per IP per hour.

**📍 Location mode**
- Rounded search box with 🔍 icon and an autocomplete dropdown (Google Places).
- **Filters** (multi-select chip row): 🌲 Dispersed/BLM · 🏗️ Paid w/ Facilities · ⛰️ Overlanding · 🚗 Car Camping · 🚌 RV Friendly · 🥾 Walk-in Only
- **Source chips** (multi-select, color-coded per source): The Dyrt · iOverlander · Recreation.gov · Campendium
- **Search radius** row: 25 / 50 / 100 / 200 mi pill buttons
- **Search history** pills above filters — recent queries, each with a tiny ✕ to remove
- A big rounded "🔍 Search" CTA

**Result cards** (used across Search, Saved, Map popup, and Card modal):
- 16:9 **photo carousel** at the top (prev/next arrows + dot indicators + blurred-bg fill for off-aspect images)
- Colored **source badge** (top-left) per data source (Dyrt=tan, Rec=sage, iOverlander=slate-blue, BLM=slate, Campendium=brown)
- **Fee badge** (top-right, e.g. "Free" or "$22/night")
- **Name** (large, serif-ish Nunito 800), **city + state** (sky-blue)
- **Pills** (feature highlights: "Dispersed", "Pit toilet", "No reservation", etc.)
- **Description** — ~2 sentences
- **Tag chips** — smaller meta (tags + location tags)
- **Weather strip** — live temp, icon, conditions, wind
- **Sun strip** — sunrise/sunset
- **Footer action row** (grid, varies by context):
  - Search result card: [Directions] [Search site] [Save] [Add to trip]
  - Saved card adds: [Delete] [Share] [Visited]
- **Notes section** (in the full Card modal) — a textarea + save button for personal notes on that spot

### 4.3 Map tab
- Top toggle row: **🔍 Search results / 🔖 Saved spots / 🧭 My route**
- Full-height Leaflet map below
- Custom popup style (dark card with campsite name, meta, and a tan "open" button)
- Floating "🔍 Search this area" button appears when the user pans; above it a small "Tap map to search that area" hint
- In route mode, the polyline connects stops in order

### 4.4 Saved tab
- Top bar "Saved Spots 🔖" with a right-aligned **Plan a trip** toggle
- **Route planner** (expands when toggled):
  - Instruction "Use ↑ ↓ to reorder your stops"
  - Two toggles: 🔄 Round trip · 📍 Start from me (current location)
  - Reorderable list of stops with up/down arrows
  - Action row: 🗺️ Open on map · **+ All** (add every saved spot) · **✦ Optimize** (nearest-neighbor reorder from GPS) · **🔗 Share** (generate a share link via Supabase) · **✓ Completed** (log trip to history + clear) · **Clear**
- **Saved filter bar** (when saved > 0): state dropdown + sort chips (📅 Date, 🔤 A-Z, 📍 Distance)
- Scrollable list of saved cards (same card component as search)

### 4.5 Settings (slide-up modal)
Grouped sections:
- **Appearance:** light mode toggle
- **Search defaults:** default radius dropdown
- **Notifications:** Enable trip reminders
- **Data:** clear buttons for Search history, Recently viewed, Home cache, Saved spots, Passport stamps, Stats & journal
- **Account:** signed-in email + Sign in/out button
- **About:** stats, site link, disclaimer, Privacy, Terms
- Footer: "NomadAI v1.0 · Made with 🏕️"

### 4.6 Profile (centered modal)
- Circular avatar (tappable to upload a photo) with camera hint overlay
- Email (read-only)
- Name input
- Save button (tan)
- Sign out link

### 4.7 Stats (slide-up modal)
- Title "Your Stats 📊"
- Lifetime stats: camps visited, trips completed, unique states, unique national parks, favorite state, average rating, etc. (derived from localStorage + Supabase sync).

### 4.8 Passport (slide-up modal)
- Title "Your Passport" with count ("0 camps visited")
- 2-column grid of stamp tiles (one per visited camp)

### 4.9 Trips history (slide-up modal)
- Reverse-chronological list of completed trips with date, stop count, and stop names.

### 4.10 Auth (centered modal)
- Title "🏕️ NomadAI"
- Sub: "Sign in to sync your saved spots across all your devices."
- Email + password inputs
- Primary Sign in button
- Toggle between Sign in / Sign up
- Legal note + "Continue without account" link

### 4.11 Full card modal
Full-screen overlay showing one campsite card expanded with everything: full photo carousel, weather, sun, description, tags, all action buttons, and the notes textarea.

### 4.12 Shared spot page (`spot.html`)
Public, unauthenticated view of a single campsite. Same card component, same dark theme, plus a top bar with a "Open app →" CTA and a bottom CTA encouraging the user to install the app.

---

## 5. Current Visual Style

### 5.1 Color palette (CSS variables)
Dark (default) theme:
- `--darker`: `#1c2820` — deep forest (page bg)
- `--dark`: `#2a3830` — one notch up (cards / inputs)
- `--card`: `#324438` — card surface
- `--sand`: `#e8d5b7` — primary text, warm off-white
- `--light`: `#d4e8d8` — secondary text, pale sage
- `--muted`: `#7a9a88` — tertiary text, dusty sage
- `--sage`: `#8aac7a` — accent (Rec.gov, success)
- `--tan`: `#c4a06a` — primary accent (CTAs, active states, "Dyrt" source)
- `--tan-dark`: `#9a7040` — overlanding accent
- `--slate`: `#6a8c8a` — borders, divider, BLM source
- `--sky`: `#a8c4cc` — location / info accent, outline buttons
- `--red`: `#e8a0a0` — destructive
- Source accent colors: Dyrt `#c4a06a` · iOverlander `#5a8898` · Rec.gov `#8aac7a` · BLM `#6a8c8a` · Campendium `#7a6a50`

Light theme:
- Background `#f0ebe0` (parchment)
- Surface `#f8f4ec`
- Text `#2a3830`
- Accents shift darker: tan → `#9a7040`, sage → `#4a8840`, slate → `#8aac8a`

Overall mood: warm, earthy, nature-grounded. Evokes BLM land, sagebrush, canvas, canyon sunsets — deliberately *not* the bright outdoorsy primary greens of most camping apps.

### 5.2 Typography
- **Body / UI:** `Nunito` (400/600/700/800) — a friendly, rounded sans-serif
- **Landing hero + section headers:** `Playfair Display` (italic variant used for emphasis, e.g. *"Start exploring."*)
- Heavy reliance on 800-weight for titles and CTAs; small 10–11px uppercase 800-weight labels with wide letter-spacing (0.1–0.16em) act as section dividers ("Filters", "Search radius", "Results", etc.)

### 5.3 Shape / radius language
- Pill/capsule buttons everywhere (border-radius 50px) — nav CTAs, source chips, filter chips, search CTAs
- Cards use 20px radius
- Inputs use 12–20px radius
- Bottom-sheet modals have 24px top corners

### 5.4 Iconography
Emoji-forward across the UI:
- Tabs use Lucide-style line SVG icons
- Content/category labels use emoji: 🏕️ ⛺ 🚙 🌲 🗺️ 🔍 📍 🔖 🧭 ✨ 🌤️ 🪪 🙋
- Source badges rely on emoji and color to be scannable

### 5.5 Patterns
- **Chips** — rounded 50px pills with a colored outline; when `on`, they flip to a filled background in that color with inverted text
- **Horizontal scrolling rows** for chips/filters/history — hide scrollbar, snap nowrap
- **Cards** — dark surface, subtle slate border, 20px radius, fade-up entry animation (`@keyframes fu`)
- **Modals** — either centered with dim backdrop, or slide-up bottom sheets with a grey handle bar
- **Bottom nav** — fixed, 4 columns, muted icon → tan when active
- **Empty / placeholder states** — muted sage text centered in ~48px padding

### 5.6 Motion
- Hero fade-up (`fadeUp` keyframe, ~0.6s, staggered 0.1s)
- Card fade-up on mount (0.3s)
- Carousel slide transition 0.35s ease
- Hover: subtle translateY(-1–2px) + opacity on CTAs
- Spinners: 0.7s linear rotate

---

## 6. Key User Flows

### Flow A — "I want a campsite near me tonight"
1. Land on Home → see trip dashboard (empty) → tap Search
2. Default to "✨ Ask AI" → type "nice free spot near me tonight with shade"
3. Claude returns 6 cards → user taps a photo → lightbox → swipes photos
4. User taps **Save** → spot moves to Saved tab, Supabase syncs if signed in
5. User taps **Directions** → Google Maps opens

### Flow B — "Plan a multi-day overland trip"
1. Search tab → "✨ Ask AI" → "dispersed BLM camps along US-50 from Carson City to Moab, 4x4 ok"
2. AI detects route query → returns 8–12 stops ordered start → end
3. User taps **Add to trip** on each → Saved tab's route planner accrues stops
4. User toggles **📍 Start from me** and **🔄 Round trip** → taps **✦ Optimize**
5. Nearest-neighbor reorders stops → user taps **🗺️** → Map tab, route mode, polyline drawn
6. User taps **🔗 Share** → share link copied
7. After the trip: **✓ Completed** → trip logged to history, stops cleared from planner, passport stamps applied

### Flow C — "I just got here, what's nearby?"
1. Map tab → pans map over unfamiliar terrain
2. "🔍 Search this area" button appears → tap
3. Location search fires for map center → cards render and pins drop

### Flow D — Beginner plain-English
1. Landing page → "Plan my route" CTA → opens app Search in AI mode
2. Types "a nice campsite near Denver this weekend"
3. Claude returns real options with photos, fees, weather — no jargon needed

---

## 7. Data Sources (to reference in design)

- **Recreation.gov** (federal campgrounds)
- **iOverlander** (crowdsourced overland spots)
- **The Dyrt** (user-rated campgrounds)
- **BLM / Dispersed** (public land free camping)
- **Campendium** (RV + boondocking)
- **Google Places** (photos, autocomplete, base info)
- **Open-Meteo** or equivalent (weather + sunrise/sunset on each card)
- **Claude** (all natural language understanding + route synthesis)

Each source needs to remain visually distinguishable in the redesign — a camper picking between BLM and Dyrt cards should be able to tell at a glance. The current solution is colored source badges top-left of each card.

---

## 8. What's Working vs. What's Up for Reimagining

### Keep / preserve
- Warm, earth-toned palette — strongly on-brand, differentiates from generic "Patagonia green" camping apps
- Single scrollable column with bottom nav — works great on phones where 90%+ of usage happens
- Card-as-atom — the same card shows up everywhere (Search / Saved / Map popup / Modal / Shared page). Consistency is a feature
- Chip-based filtering — low friction, scannable
- AI chat feels like the hero — the redesign should still make the "✨ Ask AI" input the most prominent element on the Search tab
- Pill/capsule button language

### Candidates to rethink
- **Emoji density.** Emoji shoulder a lot of the icon load; the redesign could introduce a proper icon system (custom line icons matched to the palette) and use emoji more sparingly as accents.
- **Visual hierarchy on cards.** Badges, fees, pills, tags, weather, sun, and 3–5 footer buttons can feel dense. Could benefit from progressive disclosure (collapsed "quiet" card → expanded).
- **Home dashboard.** Currently three sections (trip + stats + journal) in a simple stack. Opportunity for a more editorial, magazine-y feel — hero "current trip" card, then more editorial blocks.
- **Route planner UI.** Up/down arrow reordering feels utilitarian; a more tactile drag surface with distance between stops visualized would elevate it.
- **Map treatment.** Leaflet default tiles feel generic. A custom earthy map tile style (or a Mapbox style with dunes/sage/canyon palette) would unify the brand into the map layer.
- **Passport / stamps.** Visual opportunity: right now it's a 2-column grid. Could become the app's most "collectible" moment — treated like a real passport booklet, national park patches, or trailhead stamps.
- **Empty states.** Today they're plain centered muted text. Could become small illustrated moments that reinforce the brand voice.
- **Typography.** Pairing Nunito with Playfair Display is warm but generic. Consider a slightly more characterful serif (e.g. Fraunces, Source Serif, Canela) or a display-weight sans for headlines.

### Non-negotiable constraints
- Must stay **single-file HTML/CSS/JS** (or degrade gracefully to it) — no build step, the app is hosted as static + serverless
- Must stay **PWA-friendly** and feel native on iOS (respect safe-area-insets, no horizontal overflow, tap targets ≥ 40px)
- Max width **480px** column on desktop — design for mobile first, desktop is "a phone in the middle"
- Must keep **dark + light theme** parity
- Must keep the 4-tab bottom nav (Home / Search / Map / Saved) — this is the spine of the app
- Rate-limited AI (10/hr) means loading states and cached-hit treatments matter — both should feel intentional, not like errors

---

## 9. Brand voice reference (for UI copy)

- Confident but earthy, never salesy
- Plain English, sentence case for UI copy; Title Case reserved for section headers
- Leans into outdoor/overland vocabulary: "before you air down", "rolling into", "out there", "in the field"
- Avoids startup-speak ("unlock", "empower", "supercharge")
- Acknowledges beginners without condescending ("You don't need to know anything about BLM or dispersed camping to use NomadAI")
- Always reminds users to verify availability before visiting — trust matters when the data source is crowdsourced

---

## 10. Deliverable hopes from a redesign

In priority order:
1. A refreshed **card component** — the most-reused atom; a small improvement compounds everywhere
2. A new **Home tab** that feels like a proper dashboard rather than three stacked sections
3. An elevated **route planner** that makes the multi-stop planning feel like the headline feature it is
4. A **custom map style** that extends the brand into the map tab
5. A **passport / stamps** treatment worth showing off
6. An **icon system** to reduce emoji load without losing warmth
7. **Type + color token refinements** that keep the earthy mood but sharpen hierarchy
